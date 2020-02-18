using Test, TestPackage2


@static if Sys.iswindows()
  @test hello2("Julia") == "Hello, Julia"
else
  @test domath2(2.0) ≈ 7.0
end
