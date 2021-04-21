# CodeInfoTools.jl

| **Build Status**                                       | **Coverage**                    | **Documentation** |
|:------------------------------------------------------:|:-------------------------------:|:-----------------:|
| [![][gha-1.6-img]][gha-url] [![][gha-nightly-img]][gha-url] | [![][codecov-img]][codecov-url] | [![][dev-docs-img]][dev-docs-url] |

[gha-1.6-img]: https://github.com/JuliaCompilerPlugins/CodeInfoTools.jl/workflows/julia-1.6/badge.svg
[gha-nightly-img]: https://github.com/JuliaCompilerPlugins/CodeInfoTools.jl/workflows/julia-nightly/badge.svg
[gha-url]: https://github.com/JuliaCompilerPlugins/CodeInfoTools.jl/actions
[codecov-img]: https://codecov.io/github/JuliaCompilerPlugins/CodeInfoTools.jl/badge.svg?branch=master
[codecov-url]: https://codecov.io/github/JuliaCompilerPlugins/CodeInfoTools.jl?branch=master
[dev-docs-img]: https://img.shields.io/badge/docs-dev-blue.svg
[dev-docs-url]: https://JuliaCompilerPlugins.github.io/CodeInfoTools.jl/dev

```
] add CodeInfoTools
```

> **Note**: A curated collection of tools for the discerning `CodeInfo` connoisseur. The architecture of this package is based closely on the [Pipe construct in IRTools.jl](https://github.com/FluxML/IRTools.jl/blob/1f3f43be654a41d0db154fd16b31fdf40f30748c/src/ir/ir.jl#L814-L973). Many (if not all) of the same idioms apply.

## Motivation

Working with `CodeInfo` is often not fun. E.g. when examining the untyped expansion of the [Rosenbrock function](https://en.wikipedia.org/wiki/Rosenbrock_function)

```
CodeInfo(
    @ /Users/mccoybecker/dev/CodeInfoTools.jl/examples/simple.jl:7 within `rosenbrock'
1 ─       a = 1.0
│         b = 100.0
│         result = 0.0
│   %4  = (length)(x)
│   %5  = (-)(%4, 1)
│   %6  = (Colon())(1, %5)
│         @_3 = (iterate)(%6)
│   %8  = (===)(@_3, nothing)
│   %9  = (Core.Intrinsics.not_int)(%8)
└──       goto #4 if not %9
2 ┄ %11 = @_3
│         i = (getfield)(%11, 1)
│   %13 = (getfield)(%11, 2)
│                .
│                .
│                .
│
│   %36 = (===)(@_3, nothing)
│   %37 = (Core.Intrinsics.not_int)(%36)
└──       goto #4 if not %37
3 ─       goto #2
4 ┄       return result
)
```

Do you ever wonder -- is there another (perhaps, any) way to work with this object? A `Pipe` perhaps? Where I might load my `CodeInfo` into -- iterate, make local changes, and produce a new copy?

Fear no longer, my intuitive friend! We present `CodeInfoTools.jl` to assuage your fears and provide you (yes, you) with an assortment of tools to mangle, distort, smooth, slice, chunk, and, above all, _work with_ `CodeInfo`.

## Contribution

`CodeInfoTools.jl` provides an `Pipe` abstraction which allows you to safely iterate over and manipulate `CodeInfo`.

```julia
struct Canvas
    defs::Vector{Tuple{Int, Int}}
    code::Vector{Any}
    codelocs::Vector{Int32}
end

mutable struct Pipe
    from::CodeInfo
    to::Canvas # just the mutable bits
    map::Dict{Any, Any}
    var::Int
end

function Pipe(ci::CodeInfo)
    canv = Canvas(Tuple{Int, Int}[], Any[], Int32[])
    p = Pipe(ci, canv, Dict(), 0)
    return p
end
```

How does this work in practice?

```julia
using CodeInfoTools

function f(x, y)
    z = 10
    if z > 10
        n = 10
        return x + y
    else
        return x + y + z
    end
end

ir = code_info(f, Tuple{Int,Int})

function transform(ir)
    p = CodeInfoTools.Pipe(ir)
    for (v, st) in p
        st isa Expr || continue
        st.head == :call || continue
        st.args[1] == Base.:(+) || continue
        p[v] = Expr(:call, Base.:(*), st.args[2:end]...)
    end
    return finish(p)
end

display(ir)
display(transform(ir))
```

Here, we've lowered a function directly to a `CodeInfo` instance and shoved into a `Pipe` instance `p`. You can now safely iterate over this object, perform local changes, press `finish` and - _(la di da!)_ - out comes a new `CodeInfo` with your changes fresh.

```
# Before:
CodeInfo(
1 ─      Core.NewvarNode(:(n))
│        z = 10
│   %3 = z > 10
└──      goto #3 if not %3
2 ─      n = 10
│   %6 = x + y
└──      return %6
3 ─ %8 = x + y + z
└──      return %8
)

# After:
CodeInfo(
1 ─      Core.NewvarNode(:(n))
│        z = 10
│   %3 = (>)(z, 10)
└──      goto #3 if not %3
2 ─      n = 10
│   %6 = (*)(x, y)
└──      return %6
3 ─ %8 = (*)(x, y, z)
└──      return %8
)
```
