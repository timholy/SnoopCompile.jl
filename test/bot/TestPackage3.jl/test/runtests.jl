using Test, TestPackage3


@static if VERSION > v"1.3"
  @test hello2("Julia") == "Hello, Julia"
elseif VERSION > v"1.0"
  @test domath2(2.0) ≈ 7.0
else
  multiply3(2.0) == 8.0
end
