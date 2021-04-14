module CodeInfoTools

using Core: CodeInfo 

import Base: iterate, push!, pushfirst!, insert!, delete!, getindex, lastindex, setindex!, display, +

const Variable = Core.SSAValue

Base.:(+)(v::Variable, id::Int) = Variable(v.id + id)
Base.:(+)(id::Int, v::Variable) = Variable(v.id + id)

function code_info(f, tt; generated=true, debuginfo=:default)
    ir = code_lowered(f, tt; generated=generated, debuginfo=:default)
    isempty(ir) && return nothing
    return ir[1]
end

@doc(
"""
    code_info(f, tt; generate = true, debuginfo = :default)

Return lowered code for function `f` with tuple type `tt`. Equivalent to `InteractiveUtils.@code_lowered` -- but a function call and requires a tuple type `tt` as input.
""", code_info)

walk(fn, x) = fn(x)
walk(fn, x::Variable) = Variable(fn(x.id))
walk(fn, x::Core.ReturnNode) = Core.ReturnNode(walk(fn, x.val))
walk(fn, x::Core.GotoNode) = Core.GotoNode(walk(fn, x.label))
walk(fn, x::Core.GotoIfNot) = Core.GotoIfNot(walk(fn, x.cond), walk(fn, x.dest))
walk(fn, x::Expr) = Expr(x.head, map(a -> walk(fn, a), x.args)...)
function walk(fn, x::Vector)
    map(x) do el
        walk(fn, el)
    end
end

resolve(x) = x
resolve(gr::GlobalRef) = getproperty(gr.mod, gr.name)

#####
##### Pipe
#####

struct NewVariable
    id::Int
end

struct Canvas
    defs::Vector{Tuple{Int, Int}}
    code::Vector{Any}
    codelocs::Vector{Int32}
end
Canvas() = Canvas(Tuple{Int, Int}[], Any[], Int32[])
function getindex(c::Canvas, v)
    ind = findfirst(k -> k[2] == v, c.defs)
    ind == nothing && return
    getindex(c.code, ind)
end

function push!(c::Canvas, stmt)
    push!(c.code, stmt)
    push!(c.codelocs, Int32(1))
    l = length(c.defs) + 1
    push!(c.defs, (l, l))
    return Variable(length(c.defs))
end

function insert!(c::Canvas, idx::Int, x)
    insert!(c.code, idx, x)
    insert!(c.codelocs, idx, Int32(1))
    for i in 1 : length(c.defs)
        k, v = c.defs[i]
        if v >= idx
            c.defs[i] = (k, v + 1)
        end
    end
    push!(c.defs, (length(c.defs) + 1, idx))
    return Variable(length(c.defs))
end

function delete!(c::Canvas, idx::Int)
    deleteat!(c.code, idx)
    deleteat!(c.codelocs, idx)
    for i in 1 : length(c.defs)
        k, v = c.defs[i]
        if v > idx
            c.defs[i] = (k, v - 1)
        end
    end
    return Variable(length(c.defs))
end

pushfirst!(c::Canvas, x) = insert!(c, 1, x)

setindex!(c::Canvas, x, v::Variable) = setindex!(c.code, x, v.id)

mutable struct Pipe
    from::CodeInfo
    to::Canvas
    map::Dict{Any, Any}
    var::Int
end

function Pipe(ci::CodeInfo)
    canv = Canvas(Tuple{Int, Int}[], Any[], Int32[])
    p = Pipe(ci, canv, Dict(), 0)
    return p
end

@doc(
"""
    Pipe(ir)

A wrapper around a `Canvas` object -- allow incremental construction of `CodeInfo`. Call [`finish`](@ref) when done to produce a new `CodeInfo` instance.

In general, it is not efficient to insert statements onto your working `Canvas`; only appending is
fast, for the same reason as with `Vector`s.
For this reason, the `Pipe` construct makes it convenient to incrementally build a `Canvas` fragment from a piece of `CodeInfo`, making efficient modifications as you go.
The general pattern looks like:
```julia
pr = CodeInfoTools.Pipe(ir)
for (v, st) in pr
  # do stuff
end
ir = CodeInfoTools.finish(pr)
```
In the loop, inserting and deleting statements in `pr` around `v` is efficient.
""", Pipe)

getindex(p::Pipe, v) = getindex(p.to, v)
lastindex(p::Pipe) = length(p.to.defs)

var!(p::Pipe) = NewVariable(p.var += 1)

substitute!(p::Pipe, x, y) = (p.map[x] = y; x)
substitute(p::Pipe, x) = get(p.map, x, x)
substitute(p::Pipe, x::Variable) = p.map[x]
substitute(p::Pipe, x::Expr) = Expr(x.head, substitute.((p, ), x.args)...)
substitute(p::Pipe, x::Core.GotoNode) = Core.GotoNode(substitute(p, x.label))
substitute(p::Pipe, x::Core.GotoIfNot) = Core.GotoIfNot(substitute(p, x.cond), substitute(p, x.dest))
substitute(p::Pipe, x::Core.ReturnNode) = Core.ReturnNode(substitute(p, x.val))
substitute(p::Pipe) = x -> substitute(p, x)

function pipestate(ci::CodeInfo)
    ks = sort([Variable(i) => v for (i, v) in enumerate(ci.code)], by = x -> x[1].id)
    return first.(ks)
end

function iterate(p::Pipe, (ks, i) = (pipestate(p.from), 1))
    i > length(ks) && return
    v = ks[i]
    st = walk(resolve, p.from.code[v.id])
    substitute!(p, v, push!(p.to, substitute(p, st)))
    return ((v, st), (ks, i + 1))
end

_get(d, x, v) = x
_get(d, x::Variable, v) = get(d, x.id, v)

function renumber(c::CodeInfo)
    p = Pipe(c)
    for (v, st) in p
        if isbits(st) # Trivial expressions can be inlined
            delete!(p, v)
            substitute!(p, v, substitute(p, st))
        end
    end
    return finish(p)
end

function finish(p::Pipe)
    new_ci = copy(p.from)
    new_ci.code = p.to.code
    new_ci.codelocs = p.to.codelocs
    new_ci.slotnames = p.from.slotnames
    new_ci.slotflags = [0x00 for _ in new_ci.slotnames]
    new_ci.inferred = false
    new_ci.inlineable = p.from.inlineable
    new_ci.ssavaluetypes = length(p.to.code)
    return new_ci
end

@doc(
"""
    finish(p::Pipe)

Create a new `CodeInfo` instance from a [`Pipe`](@ref). Renumbers the wrapped `Canvas` in-place -- then copies information from the original `CodeInfo` instance and inserts modifications from the wrapped `Canvas`.
""", finish)

islastdef(c::Canvas, v) = v == length(c.defs)

setindex!(p::Pipe, x, v) = p.to[substitute(p, v)] = substitute(p, x)
function setindex!(p::Pipe, x, v::Variable)
    v′= substitute(p, v)
    if islastdef(p.to, v′)
        delete!(p, v)
        substitute!(p, v, substitute(p, x))
    else
        p.to[v′] = substitute(p, x)
    end
end

function Base.push!(p::Pipe, x)
    tmp = var!(p)
    substitute!(p, tmp, push!(p.to, substitute(p, x)))
    return tmp
end

function Base.pushfirst!(p::Pipe, x)
    tmp = var!(p)
    v = pushfirst!(p.to, substitute(p, x))
    substitute!(p, tmp, v)
    return tmp
end

function Base.delete!(p::Pipe, v)
    v′ = substitute(p, v)
    delete!(p.map, v)
    if islastdef(p.to, v′)
        pop!(p.to.defs)
        pop!(p.to.code)
    else
        delete!(p.to, v′)
    end
end

function insert!(p::Pipe, v, x::T; after = false) where T
    v′ = substitute(p, v)
    x = substitute(p, x)
    tmp = var!(p)
    if islastdef(p.to, v′)
        if after
            substitute!(p, tmp, push!(p.to, x))
        else
            substitute!(p, v, push!(p.to, p.to[v′]))
            p.to[v′] = T(x)
            substitute!(p, tmp, v′)
        end
    else
        substitute!(p, tmp, insert!(p.to, v′.id + Int(after), x))
    end
    return tmp
end

Base.display(p::Pipe) = display(finish(p))

#####
##### Exports
#####

export code_info, renumber, finish

end # module
