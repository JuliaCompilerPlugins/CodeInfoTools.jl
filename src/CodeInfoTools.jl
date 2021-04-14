module CodeInfoTools

using Core: CodeInfo 

import Base: iterate, push!, pushfirst!, insert!, replace!, display, delete!, getindex, +, setindex!

Base.:(+)(v::Core.SSAValue, id::Int) = Core.SSAValue(v.id + id)
Base.:(+)(id::Int, v::Core.SSAValue) = Core.SSAValue(v.id + id)

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

walk(fn, x) = x
walk(fn, x::Core.SSAValue) = Core.SSAValue(fn(x.id))
walk(fn, x::Core.ReturnNode) = Core.ReturnNode(walk(fn, x.val))
walk(fn, x::Core.GotoNode) = Core.GotoNode(walk(fn, x.label))
walk(fn, x::Core.GotoIfNot) = Core.GotoIfNot(walk(fn, x.cond), walk(fn, x.dest))
walk(fn, x::Expr) = Expr(x.head, map(a -> walk(fn, a), x.args)...)
function walk(fn, x::Vector)
    map(x) do el
        walk(fn, el)
    end
end

#####
##### Pipe
#####

struct Canvas
    defs::Vector{Tuple{Int, Int}}
    code::Vector{Any}
    codelocs::Vector{Int32}
end
Canvas() = Canvas(Tuple{Int, Int}[], Any[], Int32[])

function push!(c::Canvas, stmt)
    push!(c.code, stmt)
    push!(c.codelocs, Int32(1))
    return Core.SSAValue(length(c.code))
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
    return Core.SSAValue(length(c.defs))
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
    return Core.SSAValue(length(c.defs))
end

pushfirst!(c::Canvas, x) = insert!(c, 1, x)

setindex!(c, x, v) = setindex!(c.code, x, v)

mutable struct Pipe
    from::CodeInfo
    to::Canvas
    map::Dict{Any, Any}
    var::Int
end

function Pipe(ci::CodeInfo)
    canv = Canvas(Tuple{Int, Int}[(i, i) for i in 1 : length(ci.code)], Any[], Int32[])
    p = Pipe(ci, canv, Dict(), 0)
    return p
end

var!(p::Pipe) = Core.SSAValue(p.var += 1)

substitute!(p::Pipe, x, y) = (p.map[x] = y; x)
substitute(p::Pipe, x) = get(p.map, x, x)
substitute(p::Pipe, x::Core.SSAValue) = p.map[x]
substitute(p::Pipe, x::Expr) = Expr(x.head, substitute.((p, ), x.args)...)
substitute(p::Pipe, x::Core.GotoNode) = Core.GotoNode(substitute(p, x.label))
substitute(p::Pipe, x::Core.GotoIfNot) = Core.GotoIfNot(substitute(p, x.cond), substitute(b, x.dest))
substitute(p::Pipe, x::Core.ReturnNode) = Core.ReturnNode(substitute(p, x.val))
substitute(p::Pipe) = x -> substitute(p, x)

function pipestate(ci::CodeInfo)
    ks = sort([Core.SSAValue(i) => v for (i, v) in enumerate(ci.code)], by = x -> x[1].id)
    return first.(ks)
end

function iterate(p::Pipe, (ks, i) = (pipestate(p.from), 1))
    i > length(ks) && return
    v = ks[i]
    st = p.from.code[v.id]
    substitute!(p, v, push!(p.to, substitute(p, st)))
    return ((v, st), (ks, i + 1))
end

function renumber(c::Canvas)
    d = Dict(c.defs)
    n = Canvas()
    for (v, st) in enumerate(c.code)
        push!(n.code, walk(x -> get(d, x, x), st))
        push!(n.defs, (v, v))
        push!(n.codelocs, Int32(1))
    end
    return n
end

function renumber!(c::Canvas)
    d = Dict(c.defs)
    for (v, st) in enumerate(c.code)
        setindex!(c.code, walk(x -> get(d, x, x), st), v)
        setindex!(c.defs, (v, v), v)
        setindex!(c.codelocs, Int32(1), v)
    end
    return c
end

function finish(p::Pipe)
    c = renumber!(p.to)
    new_ci = copy(p.from)
    new_ci.code = c.code
    new_ci.codelocs = p.to.codelocs
    new_ci.slotnames = p.from.slotnames
    new_ci.slotflags = [0x00 for _ in new_ci.slotnames]
    new_ci.inferred = false
    new_ci.inlineable = p.from.inlineable
    new_ci.ssavaluetypes = length(p.to.code)
    return new_ci
end

islastdef(c::Canvas, v) = v == length(c.defs)

function setindex!(p::Pipe, x::Core.SSAValue, v)
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
        substitute!(p, tmp, insert!(p.to, v′ + after, x))
    end
    return tmp
end

Base.display(p::Pipe) = display(finish(p))

#####
##### Exports
#####

export code_info, Pipe, finish

end # module
