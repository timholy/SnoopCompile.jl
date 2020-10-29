using Test

using SnoopCompile

@testset "@snoopl" begin

    @snoopl "func_names.csv" "llvm_timings.yaml" begin
        @eval module M
            i(x) = x+5
            h(a::Array) = i(a[1]::Integer) + 2
            g(y::Integer) = h(Any[y])
        end;
        @eval M.g(3)
    end;

    times, info = SnoopCompile.read_snoopl("func_names.csv", "llvm_timings.yaml")

    @test length(times) == 3  # i(), h(), g()
    @test length(info) == 3  # i(), h(), g()

end