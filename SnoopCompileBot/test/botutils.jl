@testset "pathof_noload" begin
    pnl = SnoopCompileBot.pathof_noload("MatLang")
    import MatLang
    p = GoodPath(pathof(MatLang))
    @test p == pnl
end

################################################################

@testset "detectOS" begin
    if Base.Sys.iswindows()
        @test ("windows", Base.Sys.iswindows) == SnoopCompileBot.detectOS()
    elseif Base.Sys.islinux()
        @test ("linux", Base.Sys.islinux) == SnoopCompileBot.detectOS()
    elseif Base.Sys.isapple()
        @test ("apple", Base.Sys.isapple) == SnoopCompileBot.detectOS()
    end
end
################################################################
# JuliaVersionNumber

# https://github.com/JuliaLang/julia/pull/36223:
# @test SnoopCompileBot.JuliaVersionNumber("nightly") ==
      # VersionNumber(replace(Base.read("VERSION", String), "\n" => ""))
# @test thispatch(SnoopCompileBot.JuliaVersionNumber("nightly")) == thispatch(VERSION)
@test SnoopCompileBot.JuliaVersionNumber("1.2.3") == v"1.2.3"
@test SnoopCompileBot.JuliaVersionNumber(v"1.2.3") == v"1.2.3"
