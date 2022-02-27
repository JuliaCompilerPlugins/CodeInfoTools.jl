#####
##### Builder
#####

f(x) = begin
    y = 10 + x
    z = 20 + y
    q = 20 + z
    return q + 50
end

function g(x)
    try
        if x > 1
            x + g(x - 1)
        else
            return 1
        end
        while true
            println("Nice!")
        end
        return
    catch e
        return 0
    end
end

function fn(x, y)
    z = 10
    if z > 10
        n = 10
        return x + y
    else
        return x + y + z
    end
end

@testset "Builder -- iterate" begin
    ir = code_info(f, Tuple{Int})
    p = CodeInfoTools.Builder(ir)
    local c = 1
    for (v, st) in p
        @test v == var(c)
        println(getindex(p, v))
        c += 1
    end
    ir = code_info(g, Tuple{Int})
    p = CodeInfoTools.Builder(ir)
    c = 1
    for (v, st) in p
        @test v == var(c)
        c += 1
    end
end

@testset "Builder -- setindex!" begin
    ir = code_info(f, Tuple{Int})
    p = CodeInfoTools.Builder(ir)
    len = length(p.from.code)
    for (v, st) in p
        p[v] = st
    end
    ir = finish(p)
    @test length(p.to.code) == len
    for (v, st) in CodeInfoTools.Builder(ir)
        st isa Expr && st.head == :call || continue
        @test st.args[1] == Base.:(+)
    end
    ir = code_info(g, Tuple{Int})
    p = CodeInfoTools.Builder(ir)
    len = length(p.from.code)
    for (v, st) in p
        p[v] = st
    end
    ir = finish(p)
    @test length(p.to.code) == len
    for (v, st) in CodeInfoTools.Builder(ir)
        st isa Expr && st.head == :call || continue
        @test (st.args[1] in (g, Base.:(+), Base.:(-), Base.:(>), Base.println))
    end
end

@testset "Builder -- push!" begin
    ir = code_info(f, Tuple{Int})
    p = CodeInfoTools.Builder(ir)
    c = deepcopy(p.from.code)
    for (v, st) in p
    end
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 1
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 2
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 3
    @test unwrap(p[end - 3]) isa Core.ReturnNode
    ir = code_info(g, Tuple{Int})
    p = CodeInfoTools.Builder(ir)
    c = deepcopy(p.from.code)
    for (v, st) in p
    end
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 1
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 2
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == length(c) + 3
    @test unwrap(p[end - 3]) isa Core.ReturnNode
end

@testset "Builder -- pushfirst!" begin
    ir = code_info(f, Tuple{Int})
    p = CodeInfoTools.Builder(ir)
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == 1
    pushfirst!(p, Expr(:call, rand))
    @test length(p.to.code) == 2
    pushfirst!(p, Expr(:call, rand))
    @test length(p.to.code) == 3
    ir = code_info(g, Tuple{Int})
    p = CodeInfoTools.Builder(ir)
    push!(p, Expr(:call, rand))
    @test length(p.to.code) == 1
    pushfirst!(p, Expr(:call, rand))
    @test length(p.to.code) == 2
    pushfirst!(p, Expr(:call, rand))
    @test length(p.to.code) == 3
end

@testset "Builder -- delete!" begin
    ir = code_info(f, Tuple{Int})
    p = CodeInfoTools.Builder(ir)
    for (v, st) in p
    end
    display(p)
    println()
    delete!(p, var(1))
    display(p)
    println()
    insert!(p, var(2), Expr(:call, rand))
    display(p)
    println()
    display(renumber(p.to))
    println()
    display(finish(p))
    println()
end
