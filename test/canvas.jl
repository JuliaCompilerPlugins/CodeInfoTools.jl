#####
##### Canvas
#####

@testset "Canvas -- push!" begin
    c = Canvas()
    @test Variable(1) == push!(c, Statement(Expr(:call, rand)))
    @test Variable(2) == push!(c, Expr(:call, rand))
    @test Variable(3) == push!(c, Expr(:call, rand))
    @test Variable(4) == push!(c, Expr(:call, rand))
    @test Variable(5) == push!(c, Expr(:call, rand))
    @test length(c) == 5
    for i in 1 : 5
        @test c.defs[i] == (i, i)
        @test c.codelocs[i] == Int32(1)
        @test unwrap(getindex(c, i)) == Expr(:call, rand)
    end
end


@testset "Canvas -- insert!" begin
    c = Canvas()
    @test Variable(1) == push!(c, Expr(:call, rand))
    @test Variable(2) == insert!(c, 1, Statement(Expr(:call, rand)))
    @test Variable(3) == insert!(c, 1, Expr(:call, rand))
    @test Variable(4) == insert!(c, 1, Expr(:call, rand))
    @test Variable(5) == insert!(c, 1, Expr(:call, rand))
    @test length(c) == 5
    v = [5, 1, 2, 3, 4]
    for i in 1 : 5
        @test c.defs[i][2] == v[i]
    end
    c = Canvas()
    @test Variable(1) == push!(c, Expr(:call, rand))
    @test Variable(2) == pushfirst!(c, Expr(:call, rand))
    @test Variable(3) == pushfirst!(c, Expr(:call, rand))
    @test Variable(4) == pushfirst!(c, Expr(:call, rand))
    @test Variable(5) == pushfirst!(c, Expr(:call, rand))
    @test length(c) == 5
    for i in 1 : 5
        @test c.defs[i][1] == i
    end
end

@testset "Canvas -- delete!" begin
    c = Canvas()
    push!(c, Expr(:call, +, 5, 5))
    push!(c, Expr(:call, +, 10, 10))
    push!(c, Expr(:call, +, 15, 15))
    push!(c, Expr(:call, +, 20, 20))
    push!(c, Expr(:call, +, 25, 25))
    delete!(c, 4)
    @test c.defs == [(1,1), (2,2), (3,3), (4, -1), (5, 5)]
    @test unwrap(c[1]) == Expr(:call, +, 5, 5)
    @test unwrap(c[2]) == Expr(:call, +, 10, 10)
    @test unwrap(c[3]) == Expr(:call, +, 15, 15)
    @test unwrap(c[5]) == Expr(:call, +, 25, 25)
    push!(c, Expr(:call, +, 10, 10))
    delete!(c, 4)
    @test c.defs == [(1,1), (2,2), (3,3), (4, -1), (5, 5), (6, 6)]
    @test unwrap(c[1]) == Expr(:call, +, 5, 5)
    @test unwrap(c[2]) == Expr(:call, +, 10, 10)
    @test unwrap(c[3]) == Expr(:call, +, 15, 15)
    @test unwrap(c[6]) == Expr(:call, +, 10, 10)
end

@testset "Canvas -- setindex!" begin
    c = Canvas()
    push!(c, Expr(:call, +, 5, 5))
    pushfirst!(c, Expr(:call, +, 10, 10))
    pushfirst!(c, Expr(:call, +, 15, 15))
    pushfirst!(c, Expr(:call, +, 20, 20))
    pushfirst!(c, Expr(:call, +, 25, 25))

    @test unwrap(getindex(c, 1)) == Expr(:call, +, 5, 5)
    setindex!(c, Expr(:call, *, 10, 10), 1)
    @test unwrap(getindex(c, 1)) == Expr(:call, *, 10, 10)

    @test unwrap(getindex(c, 2)) == Expr(:call, +, 10, 10)
    setindex!(c, Expr(:call, *, 5, 5), 2)
    @test unwrap(getindex(c, 2)) == Expr(:call, *, 5, 5)

    @test unwrap(getindex(c, 3)) == Expr(:call, +, 15, 15)
    setindex!(c, Expr(:call, *, 10, 10), 3)
    @test unwrap(getindex(c, 3)) == Expr(:call, *, 10, 10)
end

@testset "Canvas -- renumber" begin
    c = Canvas()
    push!(c, Expr(:call, +, 5, 5))
    pushfirst!(c, Expr(:call, +, 10, 10))
    pushfirst!(c, Expr(:call, +, 15, 15))
    pushfirst!(c, Expr(:call, +, 20, 20))
    pushfirst!(c, Expr(:call, +, 25, 25))
    delete!(c, 4)
    display(c)
    println()
    c = renumber(c)
    display(c)
    println()
    @test c.defs == [(1, 1), (2, 2), (3, 3), (4, 4)]
    @test unwrap(c[1]) == Expr(:call, +, 10, 10)
    @test unwrap(c[2]) == Expr(:call, +, 15, 15)
    @test unwrap(c[3]) == Expr(:call, +, 25, 25)
    @test unwrap(c[4]) == Expr(:call, +, 5, 5)
end

@testset "Canvas -- misc." begin
    c = Canvas()
    push!(c, Expr(:call, +, 5, 5))
    pushfirst!(c, Expr(:call, +, 10, 10))
    pushfirst!(c, Expr(:call, +, 15, 15))
    pushfirst!(c, Expr(:call, +, 20, 20))
    pushfirst!(c, Expr(:call, +, 25, 25))
    insert!(c, var(1), Expr(:call, rand))
end
