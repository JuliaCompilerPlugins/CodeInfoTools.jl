using CodeInfoTools
using Documenter

makedocs(; modules=[CodeInfoTools], sitename="CodeInfoTools",
         authors="McCoy R. Becker, Xiu-Zhe (Roger) Luo, and Valentin Churavy",
         pages=["API Documentation" => "index.md"],
         format = Documenter.HTML(prettyurls = true),
         clean = true)

deploydocs(; repo="github.com/femtomc/CodeInfoTools.jl.git", push_preview=true)
