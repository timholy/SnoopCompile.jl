using SnoopCompile, Test


@testset "utilities" begin
    @test precompilePath(:MatLang) = "\"../deps/SnoopCompile/precompile/precompile_MatLang.jl\""

end
