using Test

using SnoopCompile

f(x) = 2^x + 100

@testset "basic snoop_all" begin
    # First time not empty
    tinf, snoopl_csv, snoopl_yaml, snoopc_csv =
        SnoopCompileCore.@snoop_all "snoop_all-f" f(2)

    @test length(collect(flatten(tinf))) > 1
    @test filesize(snoopl_csv) != 0
    @test filesize(snoopl_yaml) != 0
    @test filesize(snoopc_csv) != 0

    rm(snoopl_csv)
    rm(snoopl_yaml)
    rm(snoopc_csv)

    # Second run is empty because f(x) is already compiled
    tinf, snoopl_csv, snoopl_yaml, snoopc_csv =
        SnoopCompileCore.@snoop_all "snoop_all-f" f(2)

    @test length(collect(flatten(tinf))) == 1
    @test filesize(snoopl_csv) == 0
    @test filesize(snoopl_yaml) == 0
    @test filesize(snoopc_csv) == 0

    rm(snoopl_csv)
    rm(snoopl_yaml)
    rm(snoopc_csv)
end

