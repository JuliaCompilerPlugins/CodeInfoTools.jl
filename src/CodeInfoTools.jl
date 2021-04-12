module CodeInfoTools

using Core: CodeInfo, Slot
using Core.Compiler: renumber_ir_elements!

import Base: iterate, circshift!, push!, pushfirst!, insert!, replace!, display, delete!, getindex, +, deleteat!

Base.:(+)(v::Core.SSAValue, id::Int) = Core.SSAValue(v.id + id)
Base.:(+)(id::Int, v::Core.SSAValue) = Core.SSAValue(v.id + id)

apply(fn, x) = x
apply(fn, x::GlobalRef) = fn(x)
apply(fn, x::Core.NewvarNode) = x
apply(fn, x::Core.SSAValue) = fn(x)
apply(fn, x::Core.SlotNumber) = fn(x)
apply(fn, x::Core.GotoIfNot) = Core.GotoIfNot(apply(fn, x.cond), apply(fn, x.dest))
apply(fn, x::Core.GotoNode) = Core.GotoNode(apply(fn, x.label))
apply(fn, x::Core.ReturnNode) = Core.ReturnNode(apply(fn, x.val))
apply(fn, x::Expr) = Expr(x.head, map(x -> apply(fn, x), x.args)...)

_resolve(x) = x
_resolve(x::GlobalRef) = getproperty(x.mod, x.name)
resolve(x) = apply(_resolve, x)

#####
##### Builder
#####

struct Builder
    ref::CodeInfo
    code::Vector{Any}
    nargs::Int32
    codelocs::Vector{Int32}
    newslots::Dict{Int,Symbol}
    slotnames::Vector{Symbol}
    slotmap::Vector{Int}

    function Builder(ci::CodeInfo, nargs::Int; prepare=true)
        code = []
        codelocs = Int32[]
        newslots = Dict{Int, Symbol}()
        slotnames = copy(ci.slotnames)
        slotmap = fill(0, length(ci.slotnames))
        b = new(ci, code, nargs + 1, codelocs, newslots, slotnames, slotmap)
        prepare && prepare_builder!(b)
        return b
    end
end

@doc(
"""
```julia
struct Builder
    ref::CodeInfo
    code::Vector{Any}
    nargs::Int32
    codelocs::Vector{Int32}
    newslots::Dict{Int,Symbol}
    slotnames::Vector{Symbol}
    slotmap::Vector{Int}
end

Builder(ci::CodeInfo, nargs::Int; prepare=true)
```

An immutable wrapper around `CodeInfo` which allows a user to insert statements, change SSA values, insert `Core.SlotNumber` instances, etc -- without effecting the wrapped `CodeInfo` instance. 

Call `finish(b::Builder)` to produce a modified instance of `CodeInfo`.
""", Builder)

function getindex(b::Builder, i::Int)
    @assert(i <= length(b.code))
    return getindex(b.code, i)
end

function getindex(b::Builder, i::Core.SSAValue)
    return getindex(b.code, i.id)
end

@doc(
"""
    getindex(b::Builder, i::Int)
    getindex(b::Builder, i::Core.SSAValue)

Return the expression/node at index `i` from the `Vector` of lowered code statements.
""", getindex)

function iterate(b::Builder, (ks, i)=(1:length(b.code), 1))
    i <= length(ks) || return
    return (Core.SSAValue(ks[i]) => b[i], (ks, i + 1))
end

@doc(
"""
    iterate(b::Builder, (ks, i) = (1 : length(b.code), 1))

Iterate over the builder -- generating a tuple (Core.SSAValue(k), stmt) at each iteration step, where `k` is an index and `stmt` is a node or `Expr` instance.
""", iterate)

function code_info(f, tt; generated=true, debuginfo=:default)
    ir = code_lowered(f, tt; generated=generated, debuginfo=:default)
    isempty(ir) && return nothing
    return ir[1], Builder(ir[1], length(tt.parameters))
end

@doc(
"""
    code_info(f, tt; generate = true, debuginfo = :default)

Return lowered code for function `f` with tuple type `tt`. Equivalent to `InteractiveUtils.@code_lowered` -- but a function call and requires a tuple type `tt` as input.
""", code_info)

slot(b::Builder, name::Symbol) = Core.SlotNumber(findfirst(isequal(name), b.slotnames))

function _circshift_swap(st::Core.SlotNumber, deg, v::Val{true}; ch = r -> true)
    return ch(st.id) ? Core.SlotNumber(st.id + deg) : st
end
_circshift_swap(st::Core.SlotNumber, deg, v::Val{false}; ch=r -> true) = st
_circshift_swap(st::Core.SSAValue, deg, v::Val{true}; ch=r -> true) = st
function _circshift_swap(st::Core.SSAValue, deg, v::Val{false}; ch=r -> true)
    return ch(st.id) ? Core.SSAValue(st.id + deg) : st
end

function circshift!(b::Builder, deg::Int; ch=r -> true, slots::Bool=false)
    for (v, st) in b
        replace!(b, v, apply(x -> _circshift_swap(x, deg, Val(slots); ch = ch), st))
    end
end

@doc(
"""
    circshift!(b::Builder, deg::Int; ch = r -> true, slots::Bool = false)

Shift either SSA values (`slots = false`) or the `Core.SlotNumber` instances (`slots = true`) by `deg`. The Boolean function `ch` determines which subset of values are shifted and can be customized by the user.
""", circshift!)

function bump!(b::Builder, v::Int; slots=false)
    ch = l -> l >= v
    circshift!(b, 1; ch = ch, slots = slots)
end

@doc(
"""
    bump!(b::Builder, v::Int; slots = false)

Subsets all instances of `Core.SSAValue` or `Core.SlotNumber` greater than `v` and shifts them up by 1. Convenience form of `circshift!`.
""", bump!)

function slump!(b::Builder, v::Int; slots=false)
    ch = l -> l >= v
    circshift!(b, -1; ch = ch, slots = slots)
end

@doc(
"""
    slump!(b::Builder, v::Int; slots = false)

Subsets all instances of `Core.SSAValue` or `Core.SlotNumber` greater than `v` and shifts them down by 1. Convenience form of `circshift!`.
""", slump!)

function pushslot!(b::Builder, slot::Symbol)
    b.newslots[length(b.slotnames) + 1] = slot
    push!(b.slotnames, slot)
    new = Core.SlotNumber(length(b.slotnames))
    pushfirst!(b, Core.NewvarNode(new))
    return new
end

@doc(
"""
    pushslot!(b::Builder, slot::Symbol)

Insert a new slot into the IR with name `slot`. Increments all SSA value instances to preserve the correct ordering.
""", pushslot!)

function push!(b::Builder, stmt)
    push!(b.code, stmt)
    push!(b.codelocs, Int32(0))
    return b
end

@doc(
"""
    push!(b::Builder, stmt)

Push a statement to the end of `b.code`.
""", push!)

function pushfirst!(b::Builder, stmt)
    circshift!(b, 1)
    pushfirst!(b.code, stmt)
    pushfirst!(b.codelocs, Int32(0))
    return b
end

@doc(
"""
    pushfirst!(b::Builder, stmt)

Push a statement to the head of `b.code`. This call first shifts all SSA values up by 1 to preserve ordering.
""", pushfirst!)

function insert!(b::Builder, v::Int, stmt)
    v > 0 || return
    v == 1 && return pushfirst!(b, stmt)
    v > length(b.code) && return push!(b, stmt)
    bump!(b, v)
    insert!(b.code, v, stmt)
    insert!(b.codelocs, v, 0)
    return Core.SSAValue(v)
end

function insert!(b::Builder, v::Core.SSAValue, stmt)
    return insert!(b, v.id, stmt)
end

@doc(
"""
    insert!(b::Builder, v::Int, stmt)
    insert!(b::Builder, v::Core.SSAValue, stmt)

Insert an `Expr` or node `stmt` at location `v` in `b.code`. Shifts all SSA values with `id >= v` to preserve order.
""", insert!)

function replace!(b::Builder, v::Int, stmt)
    @assert(v <= length(b.code))
    b.code[v] = stmt
    return Core.SSAValue(v + 1)
end

function replace!(b::Builder, v::Core.SSAValue, stmt)
    return replace!(b, v.id, stmt)
end

@doc(
"""
    replace!(b::Builder, v::Int, stmt)
    replace!(b::Builder, v::Core.SSAValue, stmt)

Replace the `Expr` or node at location `v` with stmt.
""", replace!)

function deleteat!(b::Builder, v::Int)
    v > length(b.code) && return
    slump!(b, v)
    if b[v] isa Core.NewvarNode
        id = b[v].slot.id
        deleteat!(b.slotnames, id)
    end
    deleteat!(b.code, v)
    deleteat!(b.codelocs, v)
    return
end

function deleteat!(b::Builder, v::Core.SSAValue)
    return deleteat!(b, v.id)
end

@doc(
"""
    deleteat!(b::Builder, v::Int)
    deleteat!(b::Builder, v::Core.SSAValue)

Delete the expression or node at location `v`. If `v` indexes a `Core.NewvarNode` (which indicates a slot), the slotname is also removed from `b.slotnames`. All SSA values and slots are shifted down accordingly.
""", deleteat!)

function prepare_builder!(b::Builder)
    for (v, st) in enumerate(b.ref.code)
        push!(b, resolve(st))
    end
    return b
end

@doc(
"""
    prepare_builder!(b::Builder)

Iterate over the reference `CodeInfo` instance in `b.ref` -- pushing `Expr` instances and nodes onto the builder `b`. This function is called during `Builder` construction so that the user is presented with a copy of the `CodeInfo` in `b.ref`.
""", prepare_builder!)

function finish(b::Builder)
    new_ci = copy(b.ref)
    new_ci.code = b.code
    new_ci.codelocs = b.codelocs
    new_ci.slotnames = b.slotnames
    new_ci.slotflags = [0x00 for _ in new_ci.slotnames]
    new_ci.inferred = false
    new_ci.inlineable = true
    new_ci.ssavaluetypes = length(b.code)
    return new_ci
end

@doc(
"""
    finish(b::Builder)

Produce a new `CodeInfo` instance from a `Builder` instance `b`.
""", finish)

Base.display(b::Builder) = display(finish(b))

#####
##### Exports
#####

export code_info, Builder, slot, finish, bump!, slump!, pushslot!

end # module
