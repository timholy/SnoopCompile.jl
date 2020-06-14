
@testset "detectOS" begin
    if Base.Sys.iswindows()
        @test ("windows", Base.Sys.iswindows) == SnoopCompile.detectOS()
    elseif Base.Sys.islinux()
        @test ("linux", Base.Sys.islinux) == SnoopCompile.detectOS()
    elseif Base.Sys.isapple()
        @test ("apple", Base.Sys.isapple) == SnoopCompile.detectOS()
    end
end
################################################################
# JuliaVersionNumber

# https://github.com/JuliaLang/julia/pull/36223:
# @test SnoopCompile.JuliaVersionNumber("nightly") ==
      # VersionNumber(replace(Base.read("VERSION", String), "\n" => ""))
# @test thispatch(SnoopCompile.JuliaVersionNumber("nightly")) == thispatch(VERSION)
@test SnoopCompile.JuliaVersionNumber("1.2.3") == v"1.2.3"
@test SnoopCompile.JuliaVersionNumber(v"1.2.3") == v"1.2.3"
