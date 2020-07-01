using Documenter
using SnoopCompile

makedocs(
    sitename = "SnoopCompile",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"
    ),
    modules = [SnoopCompile.SnoopCompileCore, SnoopCompile.SnoopCompileAnalysis, SnoopCompile.SnoopCompileBot, SnoopCompile],
    pages = ["index.md", "snoopi.md", "snoopc.md", "userimg.md", "bot.md", "snoopr.md", "reference.md"]
)

deploydocs(
    repo = "github.com/timholy/SnoopCompile.jl.git",
    push_preview=true
)
