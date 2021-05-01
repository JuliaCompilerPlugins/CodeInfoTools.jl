module CodeInfoTools

using Core: CodeInfo 

import Base: iterate, push!, pushfirst!, insert!, delete!, getindex, lastindex, setindex!, display, +, length, identity, isempty, show

#####
##### Exports
#####

export code_info, var, Variable, slot, get_slot, Statement, stmt, Canvas, Builder, slot!, renumber, verify, finish, unwrap, lambda, λ

#####
##### Utilities
#####

const Variable = Core.SSAValue
var(id::Int) = Variable(id)

@doc(
"""
    const Variable = Core.SSAValue
    var(id::Int) = Variable(id)

Alias for `Core.SSAValue` -- represents a primitive register in lowered code. See the section of Julia's documentation on [lowered forms](https://docs.julialang.org/en/v1/devdocs/ast/#Lowered-form) for more information.
""", Variable)

Base.:(+)(v::Variable, id::Int) = Variable(v.id + id)
Base.:(+)(id::Int, v::Variable) = Variable(v.id + id)

function code_info(f::Function, tt::Type{T}; generated=true, debuginfo=:default) where T <: Tuple
    ir = code_lowered(f, tt; generated = generated, debuginfo = :default)
    isempty(ir) && return nothing
    return ir[1]
end

function code_info(f::Function, t::Type...; generated = true, debuginfo = :default)
    return code_info(f, Tuple{t...}; generated = generated, debuginfo = debuginfo)
end

@doc(
"""
    code_info(f::Function, tt::Type{T}; generated = true, debuginfo = :default) where T <: Tuple
    code_info(f::Function, t::Type...; generated = true, debuginfo = :default)

Return lowered code for function `f` with tuple type `tt`. Equivalent to `InteractiveUtils.@code_lowered` -- but a function call and requires a tuple type `tt` as input.
""", code_info)

slot(ind::Int) = Core.SlotNumber(ind)

function get_slot(ci::CodeInfo, s::Symbol)
    ind = findfirst(el -> el == s, ci.slotnames)
    ind === nothing && return 
    return slot(ind)
end

@doc(
"""
    get_slot(ci::CodeInfo, s::Symbol)

Get the `Core.Compiler.SlotNumber` associated with the `s::Symbol` in `ci::CodeInfo`. If there is no associated `Core.Compiler.SlotNumber`, returns `nothing`.
""", get_slot)

walk(fn, x) = fn(x)
walk(fn, x::Variable) = fn(x)
walk(fn, x::Core.SlotNumber) = fn(x)
walk(fn, x::Core.NewvarNode) = Core.NewvarNode(walk(fn, x.slot))
walk(fn, x::Core.ReturnNode) = Core.ReturnNode(walk(fn, x.val))
walk(fn, x::Core.GotoNode) = Core.GotoNode(walk(fn, x.label))
walk(fn, x::Core.GotoIfNot) = Core.GotoIfNot(walk(fn, x.cond), walk(fn, x.dest))
walk(fn, x::Expr) = Expr(x.head, map(a -> walk(fn, a), x.args)...)
function walk(fn, x::Vector)
    map(x) do el
        walk(fn, el)
    end
end

@doc(
"""
    walk(fn::Function, x)

A generic dispatch-based tree-walker which applies `fn::Function` to `x`, specialized to `Code` node types (like `Core.ReturnNode`, `Core.GotoNode`, `Core.GotoIfNot`, etc). Applies `fn::Function` to sub-fields of nodes, and then zips the result back up into the node.
""", walk)

resolve(x) = x
resolve(gr::GlobalRef) = getproperty(gr.mod, gr.name)

#####
##### Canvas
#####

struct Statement{T}
    node::T
    type::Any
end
Statement(node::T) where T = Statement(node, Union{})
unwrap(stmt::Statement) = stmt.node
walk(fn, stmt::Statement{T}) where T = Statement(walk(fn, stmt.node), stmt.type)

const stmt = Statement

@doc(
"""
    struct Statement{T}
        node::T
        type::Any
    end

A wrapper around `Core` nodes with an optional `type` field to allow for user-based local propagation and other forms of analysis. Usage of [`Builder`](@ref) or [`Canvas`](@ref) will automatically wrap or unwrap nodes when inserting or calling [`finish`](@ref) -- so the user should never see `Statement` instances directly unless they are working on type propagation.

For more information on `Core` nodes, please see Julia's documentation on [lowered forms](https://docs.julialang.org/en/v1/devdocs/ast/#Lowered-form).
""", Statement)

struct Canvas
    defs::Vector{Tuple{Int, Int}}
    code::Vector{Any}
    codelocs::Vector{Int32}
end
Canvas() = Canvas(Tuple{Int, Int}[], [], Int32[])

Base.isempty(canv::Canvas) = Base.isempty(canv.defs)

@doc(
"""
```julia
struct Canvas
    defs::Vector{Tuple{Int, Int}}
    code::Vector{Any}
    codelocs::Vector{Int32}
end
Canvas() = Canvas(Tuple{Int, Int}[], [], Int32[])
```

A `Vector`-like abstraction for `Core` code nodes.

Properties to keep in mind:

1. Insertion anywhere is slow.
2. Pushing to beginning is slow.
2. Pushing to end is fast.
3. Deletion is fast. 
4. Accessing elements is fast.
5. Setting elements is fast.

Thus, if you build up a `Canvas` instance incrementally, everything should be fast.
""", Canvas)

length(c::Canvas) = length(filter(x -> x[2] > 0, c.defs))

function getindex(c::Canvas, idx::Int)
    r, ind = c.defs[idx]
    @assert ind > 0
    getindex(c.code, r)
end
getindex(c::Canvas, v::Variable) = getindex(c, v.id)

function push!(c::Canvas, stmt::Statement)
    push!(c.code, stmt)
    push!(c.codelocs, Int32(1))
    l = length(c.defs) + 1
    push!(c.defs, (l, l))
    return Variable(length(c.defs))
end

function push!(c::Canvas, node)
    push!(c.code, Statement(node))
    push!(c.codelocs, Int32(1))
    l = length(c.defs) + 1
    push!(c.defs, (l, l))
    return Variable(length(c.defs))
end

function insert!(c::Canvas, idx::Int, x::Statement)
    r, ind = c.defs[idx]
    @assert(ind > 0)
    push!(c.code, x)
    push!(c.codelocs, Int32(1))
    for i in 1 : length(c.defs)
        r, k = c.defs[i]
        if k > 0 && k >= ind
            c.defs[i] = (r, k + 1)
        end
    end
    push!(c.defs, (length(c.defs) + 1, ind))
    return Variable(length(c.defs))
end

function insert!(c::Canvas, idx::Int, x)
    r, ind = c.defs[idx]
    @assert(ind > 0)
    push!(c.code, Statement(x))
    push!(c.codelocs, Int32(1))
    for i in 1 : length(c.defs)
        r, k = c.defs[i]
        if k > 0 && k >= ind
            c.defs[i] = (r, k + 1)
        end
    end
    push!(c.defs, (length(c.defs) + 1, ind))
    return Variable(length(c.defs))
end
insert!(c::Canvas, v::Variable, x) = insert!(c, v.id, x)

pushfirst!(c::Canvas, x) = isempty(c.defs) ? push!(c, x) : insert!(c, 1, x)

setindex!(c::Canvas, x::Statement, v::Int) = setindex!(c.code, x, v)
setindex!(c::Canvas, x, v::Int) = setindex!(c, Statement(x), v)
setindex!(c::Canvas, x, v::Variable) = setindex!(c, x, v.id)

function delete!(c::Canvas, idx::Int)
    c.code[idx] = nothing
    c.defs[idx] = (idx, -1)
end
delete!(c::Canvas, v::Variable) = delete!(c, v.id)

_get(d::Dict, c, k) = c
_get(d::Dict, c::Variable, k) = haskey(d, c.id) ? Variable(getindex(d, c.id)) : nothing

function renumber(c::Canvas)
    s = sort(filter(v -> v[2] > 0, c.defs); by = x -> x[2])
    d = Dict((s[i][1], i) for  i in 1 : length(s))
    ind = first.(s)
    swap = walk(k -> _get(d, k, k), c.code)
    return Canvas(Tuple{Int, Int}[(i, i) for i in 1 : length(s)], 
                  getindex(swap, ind), getindex(c.codelocs, ind))
end

#####
##### Pretty printing
#####

print_stmt(io::IO, ex) = print(io, ex)
print_stmt(io::IO, ex::Expr) = print_stmt(io::IO, Val(ex.head), ex)

const tab = "  "

function show(io::IO, c::Canvas)
    indent = get(io, :indent, 0)
    bs = get(io, :bindings, Dict())
    for (r, ind) in sort(c.defs; by = x -> x[2])
        ind > 0 || continue
        println(io)
        print(io, tab^indent, "  ")
        print(io, string("%", r), " = ")
        ex = get(c.code, r, nothing)
        ex == nothing ? print(io, "nothing") : print_stmt(io, unwrap(ex))
        if unwrap(ex) isa Expr
            ex.type !== Union{} && print(io, "::$(ex.type)")
        end
    end
end

print_stmt(io::IO, ::Val, ex) = print(io, ex)

function print_stmt(io::IO, ::Val{:enter}, ex)
    print(io, "try (outer %$(ex.args[1]))")
end

function print_stmt(io::IO, ::Val{:leave}, ex)
    print(io, "end try (start %$(ex.args[1]))")
end

function print_stmt(io::IO, ::Val{:pop_exception}, ex)
    print(io, "pop exception $(ex.args[1])")
end

#####
##### Builder
#####

struct NewVariable
    id::Int
end

mutable struct Builder
    from::CodeInfo
    to::Canvas
    map::Dict{Any, Any}
    slots::Vector{Symbol}
    var::Int
end

function Builder(ci::CodeInfo)
    canv = Canvas()
    p = Builder(ci, canv, Dict(), Symbol[], 0)
    return p
end

@doc(
"""
    Builder(ir)

A wrapper around a [`Canvas`](@ref) instance. Call [`finish`](@ref) when done to produce a new `CodeInfo` instance.
""", Builder)

function get_slot(b::Builder, s::Symbol)
    s = get_slot(b.from, s)
    s === nothing || return s
    ind = findfirst(k -> k == s, b.slots)
    return ind === nothing ? s : slot(ind)
end

# This is used to handle NewVariable instances.
substitute!(b::Builder, x, y) = (b.map[x] = y; x)
substitute(b::Builder, x) = get(b.map, x, x)
substitute(b::Builder, x::Expr) = Expr(x.head, substitute.((b, ), x.args)...)
substitute(b::Builder, x::Core.GotoNode) = Core.GotoNode(substitute(b, x.label))
substitute(b::Builder, x::Core.GotoIfNot) = Core.GotoIfNot(substitute(b, x.cond), substitute(b, x.dest))
substitute(b::Builder, x::Core.ReturnNode) = Core.ReturnNode(substitute(b, x.val))

length(b::Builder) = length(b.to)

getindex(b::Builder, v) = getindex(b.to, v)
function getindex(b::Builder, v::Union{Variable, NewVariable})
    tg = substitute(b, v)
    return getindex(b.to, tg)
end

lastindex(b::Builder) = length(b.to)

function pipestate(ci::CodeInfo)
    ks = sort([Variable(i) => v for (i, v) in enumerate(ci.code)], by = x -> x[1].id)
    return first.(ks)
end

function iterate(b::Builder, (ks, i) = (pipestate(b.from), 1))
    i > length(ks) && return
    v = ks[i]
    st = walk(resolve, b.from.code[v.id])
    substitute!(b, v, push!(b.to, substitute(b, st)))
    return ((v, st), (ks, i + 1))
end

@doc(
"""
    iterate(b::Builder, (ks, i) = (pipestate(p.from), 1))

Iterate over the original `CodeInfo` and add statements to a target [`Canvas`](@ref) held by `b::Builder`. `iterate` builds the [`Canvas`](@ref) in place -- it also resolves local `GlobalRef` instances to their global values in-place at the function argument (the 1st argument) of `Expr(:call, ...)` instances. `iterate` is the key to expressing idioms like:

```julia
for (v, st) in b
    b[v] = swap(st)
end
```

At each step of the iteration, a new node is copied from the original `CodeInfo` to the target [`Canvas`](@ref) -- and the user is allowed to `setindex!`, `push!`, or otherwise change the target [`Canvas`](@ref) before the next iteration. The naming of `Core.SSAValues` is taken care of to allow this.
""", iterate)

var!(b::Builder) = NewVariable(b.var += 1)

function Base.push!(b::Builder, x)
    tmp = var!(b)
    v = push!(b.to, substitute(b, x))
    substitute!(b, tmp, v)
    return tmp
end

function Base.pushfirst!(b::Builder, x)
    tmp = var!(b)
    v = pushfirst!(b.to, substitute(b, x))
    substitute!(b, tmp, v)
    return tmp
end

function setindex!(b::Builder, x, v::Union{Variable, NewVariable})
    k = substitute(b, v)
    setindex!(b.to, substitute(b, x), k)
end

function insert!(b::Builder, v::Union{Variable, NewVariable}, x; after = false)
    v′ = substitute(b, v).id
    x = substitute(b, x)
    tmp = var!(b)
    substitute!(b, tmp, insert!(b.to, v′ + after, x))
    return tmp
end

function Base.delete!(b::Builder, v::Union{Variable, NewVariable})
    v′ = substitute(b, v)
    delete!(b.to, v′)
end

function slot!(b::Builder, name::Symbol)
    @assert(get_slot(b, name) === nothing)
    push!(b.slots, name)
    ind = length(b.from.slotnames) + length(b.slots)
    s = slot(ind)
    pushfirst!(b, Core.NewvarNode(s))
    return s
end

function verify(src::Core.CodeInfo)
    Core.Compiler.validate_code(src)
    @assert(!isempty(src.linetable))
end

@doc(
"""
    verify(src::Core.CodeInfo)

Validate `Core.CodeInfo` instances using `Core.Compiler.verify`. Also explicitly checks that the linetable in `src::Core.CodeInfo` is not empty.
""", verify)

function check_empty_canvas(b::Builder)
    isempty(b.to) && error("Builder has empty `c::Canvas` instance. This means you haven't added anything, or you've accidentally wiped the :defs subfield of `c::Canvas`.")
end

function finish(b::Builder; validate = true)
    check_empty_canvas(b)
    new_ci = copy(b.from)
    c = renumber(b.to)
    new_ci.code = map(unwrap, c.code)
    new_ci.codelocs = c.codelocs
    new_ci.slotnames = copy(b.from.slotnames)
    append!(new_ci.slotnames, b.slots)
    new_ci.slotflags = copy(b.from.slotflags)
    append!(new_ci.slotflags, [0x18 for _ in b.slots])
    new_ci.inferred = false
    new_ci.inlineable = b.from.inlineable
    new_ci.ssavaluetypes = length(b.to)
    validate && verify(new_ci)
    return new_ci
end

@doc(
"""
    finish(b::Builder)

Create a new `CodeInfo` instance from a [`Builder`](@ref). Renumbers the wrapped [`Canvas`](@ref) in-place -- then copies information from the original `CodeInfo` instance and inserts modifications from the wrapped [`Canvas`](@ref)
""", finish)

Base.display(b::Builder) = display(b.to)
function Base.identity(b::Builder)
    for (v, st) in b
    end
    return b
end

#####
##### Evaluation
#####

function lambda(m::Module, src::Core.CodeInfo)
    verify(src)
    inds = findall(==(0x00), src.slotflags)
    @assert(inds !== nothing)
    args = getindex(src.slotnames, inds)[2 : end]
    @eval m @generated function $(gensym())($(args...))
        return $src
    end
end

function lambda(m::Module, src::Core.CodeInfo, nargs::Int)
    verify(src)
    @debug "Warning: using explicit `nargs` to construct the generated function. If this number does not match the correct number of arguments in the :slotflags field of `src::Core.CodeInfo`, this can lead to segfaults and other bad behavior."
    args = src.slotnames[2 : 1 + nargs]
    @eval m @generated function $(gensym())($(args...))
        return $src
    end
end

lambda(src::Core.CodeInfo) = lambda(Main, src)
lambda(src::Core.CodeInfo, nargs::Int) = lambda(Main, src, nargs)

const λ = lambda

@doc(
"""
    lambda(m::Module, src::Core.CodeInfo)
    lambda(m::Module, src::Core.CodeInfo, nargs::Int)
    const λ = lambda

Create an anonymous `@generated` function from a piece of `src::Core.CodeInfo`. The `src::Core.CodeInfo` is checked for consistency by [`verify`](@ref).

`lambda` has a 2 different forms. The first form, given by signature:

```julia
lambda(m::Module, src::Core.CodeInfo)
```

tries to detect the correct number of arguments automatically. This may fail (for any number of internal reasons). Expecting this, the second form, given by signature:

```julia
lambda(m::Module, src::Core.CodeInfo, nargs::Int)
```

allows the user to specify the number of arguments via `nargs`.

**Note**: it is relatively difficult to prevent the user from shooting themselves in the foot with this sort of functionality. Please be aware of this. Segfaults should be cautiously expected.
""", lambda)

end # module
