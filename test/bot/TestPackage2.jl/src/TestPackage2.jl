module TestPackage2
export hello2, domath2

@static if Sys.iswindows()
  hello2(who::String) = "Hello, $who"

else
  domath2(x::Number) = x + 5

end

end
