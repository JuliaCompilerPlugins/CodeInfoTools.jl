module CodeInfoTools

using Core: CodeInfo, Slot
using Core.Compiler: NewSSAValue, renumber_ir_elements!

import Base: iterate, circshift!, push!, pushfirst!, insert!, replace!, display, delete!, getindex

resolve(x) = x
resolve(x::GlobalRef) = getproperty(x.mod, x.name)
resolve(x::Expr) = Expr(x.head, map(resolve, x.args)...)
resolve(x::Core.NewvarNode) = x
resolve(x::Core.GotoIfNot) = Core.GotoIfNot(resolve(x.cond), resolve(x.dest))
resolve(x::Core.SlotNumber) = x
resolve(x::Core.ReturnNode) = Core.ReturnNode(resolve(x.val))

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
    changemap::Vector{Int}
    slotmap::Vector{Int}

    function Builder(ci::CodeInfo, nargs::Int; prepare=true)
        code = []
        codelocs = Int32[]
        newslots = Dict{Int,Symbol}()
        slotnames = copy(ci.slotnames)
        changemap = fill(0, length(ci.code))
        slotmap = fill(0, length(ci.slotnames))
        b = new(ci, code, nargs + 1, codelocs, newslots, slotnames, changemap, slotmap)
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
    changemap::Vector{Int}
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

@doc(
"""
    getindex(b::Builder, i::int)

Return the expression/node at index `i` from the `Vector{Any}` of lowered code statements.
""", getindex)

function iterate(b::Builder, (ks, i) = (1:length(b.code), 1))
    i <= length(ks) || return
    if b[i] isa Expr && b[i].head == :(=)
        return (Core.SSAValue(ks[i]) => b[i].args[2], (ks, i + 1))
    end
    return (Core.SSAValue(ks[i]) => b[i], (ks, i + 1))
end

@doc(
"""
    iterate(b::Builder, (ks, i) = (1 : length(b.code), 1))

Iterate over the builder -- generating a tuple (k, stmt) at each iteration step, where `k` is an index and `stmt` is a node or `Expr` instance.
""", iterate)

function code_info(f, tt; generated=true, debuginfo=:default)
    ir = code_lowered(f, tt; generated=generated, debuginfo=:default)
    isempty(ir) && return nothing
    return ir[1], Builder(ir[1], length(tt.parameters))
end

@doc(
"""
    code_info(f, tt; generate = true, debuginfo = :default)

Return lowered code for function `f` with tuple type `tt`.
""", code_info)

slot(b::Builder, name::Symbol) = Core.SlotNumber(findfirst(isequal(name), ci.slotnames))

_circshift_swap(st, deg, v; ch=r -> true) = st
function _circshift_swap(st::Core.SlotNumber, deg, v::Val{true}; ch=r -> true)
    return Core.SlotNumber(st.id + deg)
end
_circshift_swap(st::Core.SlotNumber, deg, v::Val{false}; ch=r -> true) = st
_circshift_swap(st::Core.SSAValue, deg, v::Val{true}; ch=r -> true) = st
function _circshift_swap(st::Core.SSAValue, deg, v::Val{false}; ch=r -> true)
    return ch(st.id) ? Core.SSAValue(st.id + deg) : st
end
function _circshift_swap(st::Core.GotoNode, deg, v; ch=r -> true)
    return Core.GotoNode(_circshift_swap(st.label, deg, v; ch=ch))
end
function _circshift_swap(st::Core.GotoIfNot, deg, v; ch=r -> true)
    return Core.GotoIfNot(_circshift_swap(st.cond, deg, v; ch=ch),
        _circshift_swap(st.dest, deg, v; ch=ch))
end
function _circshift_swap(st::Core.ReturnNode, deg, v; ch=r -> true)
    return Core.ReturnNode(_circshift_swap(st.val, deg, v; ch=ch))
end
function _circshift_swap(st::Expr, deg, v; ch=r -> true)
    return Expr(st.head, map(e -> _circshift_swap(e, deg, v; ch=ch), st.args)...)
end
function circshift!(b::Builder, deg::Int; ch=r -> true, slots::Bool=false)
    for (v, st) in b
        replace!(b, v, _circshift_swap(st, deg, Val(slots); ch=ch))
    end
end

@doc(
"""
    circshift!(b::Builder, deg::Int; ch = r -> true, slots::Bool = false)

Shift either the SSA values (slots = false) or the `Core.SlotNumber` instances (slots = true) selected by `ch` by `deg`.
""", circshift!)

function bump!(b::Builder, v::Int; slots=false)
    ch = l -> l >= v
    for (v, st) in b
        replace!(b, v, _circshift_swap(st, 1, Val(slots); ch=ch))
    end
end

@doc(
"""
    bump!(b::Builder, v::Int; slots = false)

Increase either the SSA values (slots = false) or the `Core.SlotNumber` instances for which `id >= v` by 1.
""", bump!)

function pushslot!(b::Builder, slot::Symbol)
    circshift!(b, 1; slots=false)
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

function push!(b::Builder, stmt, codeloc::Int32=Int32(0))
    push!(b.code, stmt)
    push!(b.codelocs, codeloc)
    return b
end

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
    bump!(b, v)
    insert!(b.code, v, stmt)
    insert!(b.codelocs, v, 1)
    b.changemap[v] += 1
    return SSAValue(v)
end

insert!(b::Builder, v::Core.SSAValue, stmt) = insert!(b.code, v.id, stmt)

@doc(
"""
    insert!(b::Builder, v::Int, stmt)

Insert an `Expr` or node `stmt` at location `v` in `b.code`. Shifts all SSA values with `id >= v` to preserve order.
""", insert!)

function replace!(b::Builder, v::Int, stmt)
    @assert(v <= length(b.codelocs))
    b.code[v] = stmt
    return NewSSAValue(v + 1)
end

function replace!(b::Builder, v::Core.SSAValue, stmt)
    @assert(v.id <= length(b.codelocs))
    b.code[v.id] = stmt
    return NewSSAValue(v.id + 1)
end

@doc(
"""
    replace!(b::Builder, v::Int, stmt)

Replace the `Expr` or node at location `v` with stmt.
""", replace!)

function update_slots(e, slotmap)
    e isa Core.SlotNumber && return Core.SlotNumber(e.id + slotmap[e.id])
    e isa Expr && return Expr(e.head, map(x -> update_slots(x, slotmap), e.args)...)
    e isa Core.NewvarNode &&
    return Core.NewvarNode(Core.SlotNumber(e.slot.id + slotmap[e.slot.id]))
    return e
end

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

function _replace_new_ssavalue(e)
    e isa NewSSAValue && return SSAValue(e.id)
    e isa Expr && return Expr(e.head, map(_replace_new_ssavalue, e.args)...)
    if e isa Core.GotoIfNot
        cond = e.cond
        if cond isa NewSSAValue
            cond = SSAValue(cond.id)
        end
        return Core.GotoIfNot(cond, e.dest)
    end
    e isa Core.ReturnNode &&
    isdefined(e, :val) &&
    isa(e.val, NewSSAValue) &&
    return Core.ReturnNode(SSAValue(e.val.id))
    return e
end

function replace_new_ssavalue(code::Vector)
    return [_replace_new_ssavalue(code[idx]) for idx in 1:length(code)]
end

function finish(b::Builder)
    renumber_ir_elements!(b.code, b.changemap)
    code = replace_new_ssavalue(b.code)
    new_ci = copy(b.ref)
    new_ci.code = code
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

export code_info, Builder, finish, bump!

end # module
