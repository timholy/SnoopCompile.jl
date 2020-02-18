using Test, TestPackage


@static if Sys.iswindows()
  @test hello("Julia") == "Hello, Julia"

elseif Sys.islinux()
  @test domath(2.0) ≈ 7.0

end
