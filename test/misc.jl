
@testset "Base.:(+) -- SSAValues" begin
    @test (+)(Core.SSAValue(1), 1) == Core.SSAValue(2)
    @test (+)(1, Core.SSAValue(1)) == Core.SSAValue(2)
end

@testset "Pipe -- misc." begin
    ir = code_info(g, Tuple{Int})
    p = CodeInfoTools.Pipe(ir)
    for (v, st) in p
    end
    display(p)
    display(length(p))
    p = CodeInfoTools.Pipe(ir)
    p = identity(p)
    get_slot(p, :x)
end
