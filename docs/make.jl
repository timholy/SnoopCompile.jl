using Documenter
using SnoopCompile
import PyPlot   # so that the visualizations.jl file is loaded

makedocs(
    sitename = "SnoopCompile",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"
    ),
    modules = [SnoopCompile.SnoopCompileCore, SnoopCompile],
    linkcheck = false,   # FIXME make true
    # doctest = :fix,
    warnonly=true,
    pages = ["index.md",
             "Basic tutorials" => ["tutorials/invalidations.md", "tutorials/snoop_inference.md", "tutorials/snoop_llvm.md", "tutorials/pgdsgui.md", "tutorials/jet.md"],
             "Advanced tutorials" => ["tutorials/snoop_inference_analysis.md", "tutorials/snoop_inference_parcel.md"],
             "Explanations" => ["tools.md", "gotchas.md", "explanations/fixing_inference.md"],
             "reference.md",
    ]
)

deploydocs(
    repo = "github.com/timholy/SnoopCompile.jl.git",
    push_preview=true
)
