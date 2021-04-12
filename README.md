# CodeInfoTools.jl

| **Build Status**                                       | **Coverage**                    | **Documentation** |
|:------------------------------------------------------:|:-------------------------------:|:-----------------:|
| [![][gha-1.6-img]][gha-url] [![][gha-nightly-img]][gha-url] | [![][codecov-img]][codecov-url] | [![][dev-docs-img]][dev-docs-url] |

[gha-1.6-img]: https://github.com/femtomc/CodeInfoTools.jl/workflows/julia-1.6/badge.svg
[gha-nightly-img]: https://github.com/femtomc/CodeInfoTools.jl/workflows/julia-nightly/badge.svg
[gha-url]: https://github.com/femtomc/CodeInfoTools.jl/actions
[codecov-img]: https://codecov.io/github/femtomc/CodeInfoTools.jl/badge.svg?branch=master
[codecov-url]: https://codecov.io/github/femtomc/CodeInfoTools.jl?branch=master
[dev-docs-img]: https://img.shields.io/badge/docs-dev-blue.svg
[dev-docs-url]: https://femtomc.github.io/CodeInfoTools.jl/dev

```
] add CodeInfoTools
```

> A curated collection of tools for the discerning `CodeInfo` connoisseur.

## Motivation

Working with untyped `CodeInfo` is often not fun. E.g. when examining the untyped expansion of the [Rosenbrock function](https://en.wikipedia.org/wiki/Rosenbrock_function)

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
│   %14 = result
│   %15 = a
│   %16 = (getindex)(x, i)
│   %17 = (-)(%15, %16)
│   %18 = (Core.apply_type)(Val, 2)
│   %19 = (%18)()
│   %20 = (Base.literal_pow)(^, %17, %19)
│   %21 = b
│   %22 = (+)(i, 1)
│   %23 = (getindex)(x, %22)
│   %24 = (getindex)(x, i)
│   %25 = (Core.apply_type)(Val, 2)
│   %26 = (%25)()
│   %27 = (Base.literal_pow)(^, %24, %26)
│   %28 = (-)(%23, %27)
│   %29 = (Core.apply_type)(Val, 2)
│   %30 = (%29)()
│   %31 = (Base.literal_pow)(^, %28, %30)
│   %32 = (*)(%21, %31)
│   %33 = (+)(%20, %32)
│         result = (+)(%14, %33)
│         @_3 = (iterate)(%6, %13)
│   %36 = (===)(@_3, nothing)
│   %37 = (Core.Intrinsics.not_int)(%36)
└──       goto #4 if not %37
3 ─       goto #2
4 ┄       return result
)
```

Do you ever wonder -- is there another (perhaps, any) way to work with this object? A `Builder` perhaps? Where I might load my `CodeInfo` into -- iterate, make local changes, and produce a new copy?

Fear no longer, my intuitive friend! We present `CodeInfoTools.jl` to assuage your fears and provide you (yes, you) with an assortment of tools to mangle, distort, smooth, slice, chunk, and, above all, _work with_ `CodeInfo`.

## Contribution

`CodeInfoTools.jl` provides an IR `Builder` abstraction which allows you to safely iterate over and manipulate `CodeInfo`.

```julia
struct Builder
    ref::CodeInfo
    code::Vector{Any}
    nargs::Int32
    codelocs::Vector{Int32}
    newslots::Dict{Int,Symbol}
    slotnames::Vector{Symbol}
    slotmap::Vector{Int}

    function Builder(ci::CodeInfo, nargs::Int)
        code = []
        codelocs = Int32[]
        newslots = Dict{Int,Symbol}()
        slotnames = copy(ci.slotnames)
        slotmap = fill(0, length(ci.slotnames))
        b = new(ci, code, nargs + 1, codelocs, newslots, slotnames, slotmap)
        prepare_builder!(b)
        return b
    end
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

ir, b = code_info(f, Tuple{Int,Int})

function transform(b)
    for (v, st) in b
        st isa Expr || continue
        st.head == :call || continue
        st.args[1] == Base.:(+) || continue
        replace!(b, v, Expr(:call, Base.:(*), st.args[2:end]...))
    end
    return finish(b)
end

display(ir)
display(transform(b))
```

Here, we've lowered a function directly to a `CodeInfo` instance and shoved into a `Builder` instance `b`. You can now safely iterate over this object, perform local changes with `replace!`, press `finish` and - _(la di da!)_ - out comes a new `CodeInfo` with your changes fresh.

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
