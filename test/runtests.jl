module TestCodeInfoTools

using CodeInfoTools
using Test

f(x) = begin
    y = 10 + x
    z = 20 + y
    q = 20 + z
    return q + 50
end

g(x) = begin
    if x > 1
        x + g(x - 1)
    else
        return 1
    end
    while true
        println("Nice!")
    end
    return
end

@testset "code_info" begin
    ir = code_info(f, Int)
    @test ir == nothing
    ir = code_info(f, Tuple{Int})
    @test ir != nothing
    ir = code_info(g, Tuple{Int})
    @test ir != nothing
end

@testset "iterate" begin
    ir = code_info(f, Tuple{Int})
    p = CodeInfoTools.Pipe(ir)
    local c = 1
    for (v, st) in p
        @test v == Core.SSAValue(c)
        c += 1
    end
    ir = code_info(g, Tuple{Int})
    p = CodeInfoTools.Pipe(ir)
    c = 1
    for (v, st) in p
        @test v == Core.SSAValue(c)
        c += 1
    end
end

@testset "setindex!" begin
    ir = code_info(f, Tuple{Int})
    p = CodeInfoTools.Pipe(ir)
    len = length(p.from.code)
    for (v, st) in p
        println(v)
        p[v] = st
    end
    ir = finish(p)
    @test length(p.to.code) == len
    for (v, st) in CodeInfoTools.Pipe(ir)
        st isa Expr && st.head == :call || continue
        @test st.args[1] == Base.:(+)
    end
    ir = code_info(g, Tuple{Int})
    p = CodeInfoTools.Pipe(ir)
    len = length(p.from.code)
    for (v, st) in p
        p[v] = st
    end
    ir = finish(p)
    @test length(p.to.code) == len
    for (v, st) in CodeInfoTools.Pipe(ir)
        st isa Expr && st.head == :call || continue
        @test (st.args[1] in (g, Base.:(+), Base.:(-), Base.:(>), Base.println))
    end
end

@testset "pushfirst!" begin
    ir = code_info(f, Tuple{Int})
    p = CodeInfoTools.Pipe(ir)
    pushfirst!(p, Expr(:call, rand))
    @test length(p.to.code) == 1
    pushfirst!(p, Expr(:call, rand))
    @test length(p.to.code) == 2
    pushfirst!(p, Expr(:call, rand))
    @test length(p.to.code) == 3
    ir = code_info(g, Tuple{Int})
    p = CodeInfoTools.Pipe(ir)
    pushfirst!(p, Expr(:call, rand))
    @test length(p.to.code) == 1
    pushfirst!(p, Expr(:call, rand))
    @test length(p.to.code) == 2
    pushfirst!(p, Expr(:call, rand))
    @test length(p.to.code) == 3
end

@testset "push!" begin
    ir = code_info(f, Tuple{Int})
    p = CodeInfoTools.Pipe(ir)
    c = deepcopy(p.from.code)
    for (v, st) in p
    end
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 1
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 2
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 3
    @test p[end - 3] isa Core.ReturnNode
    ir = code_info(g, Tuple{Int})
    p = CodeInfoTools.Pipe(ir)
    c = deepcopy(p.from.code)
    for (v, st) in p
    end
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 1
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 2
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 3
    @test p[end - 3] isa Core.ReturnNode
end

@testset "delete!" begin
    ir = code_info(f, Tuple{Int})
    p = CodeInfoTools.Pipe(ir)
    len = length(p.from.code)
    for (v, st) in p
    end
    display(p)
    renumber(p.to)
    display(p)
    insert!(p, Core.SSAValue(1), Expr(:call, Base.:(*), 5, 3))
    insert!(p, Core.SSAValue(3), Expr(:call, Base.:(*), 5, 3))
    delete!(p, 3)
    delete!(p, 1)
    @test length(p.to.code) == len
    @test CodeInfoTools.walk(CodeInfoTools.resolve, p.from.code) == finish(p).code
    display(p)
    pushfirst!(p, Expr(:call, rand))
    pushfirst!(p, Expr(:call, rand))
    display(p)
    pushfirst!(p, Expr(:call, rand))
    display(p)
    delete!(p, 1)
    delete!(p, 1)
    delete!(p, 1)
    display(p)
    @test CodeInfoTools.walk(CodeInfoTools.resolve, p.from.code) == finish(p).code
    ir = code_info(g, Tuple{Int})
    p = CodeInfoTools.Pipe(ir)
    len = length(p.from.code)
    for (v, st) in p
    end
    display(p)
    insert!(p, Core.SSAValue(1), Expr(:call, Base.:(*), 5, 3))
    insert!(p, Core.SSAValue(3), Expr(:call, Base.:(*), 5, 3))
    delete!(p, 3)
    delete!(p, 1)
    @test length(p.to.code) == len
    @test CodeInfoTools.walk(CodeInfoTools.resolve, p.from.code) == finish(p).code
    display(p)
    pushfirst!(p, Expr(:call, rand))
    pushfirst!(p, Expr(:call, rand))
    display(p)
    pushfirst!(p, Expr(:call, rand))
    display(p)
    delete!(p, 1)
    delete!(p, 1)
    delete!(p, 1)
    display(p)
    @test CodeInfoTools.walk(CodeInfoTools.resolve, p.from.code) == finish(p).code
    delete!(p, length(p.to.code))
end

@testset "Base.:(+) -- SSAValues" begin
    @test (+)(Core.SSAValue(1), 1) == Core.SSAValue(2)
    @test (+)(1, Core.SSAValue(1)) == Core.SSAValue(2)
end

end # module
