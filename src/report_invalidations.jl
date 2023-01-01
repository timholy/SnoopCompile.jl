# This file is loaded conditionally via @require if PrettyTables is loaded

import .PrettyTables

export report_invalidations

function report_invalidations(;
        job_name::String = "",
        invalidations,
        n_rows::Int = 10,
        process_filename::Function = x -> x,
    )
    trees = reverse(invalidation_trees(invalidations))
    n_total_invalidations = length(uinvalidated(invalidations))
    # TODO: Merge `@info` statement with one below
    invs_per_method = map(trees) do methinvs
        countchildren(methinvs)
    end
    n_invs_total = length(invs_per_method)
    truncated_invs = n_rows < n_invs_total
    sum_invs = sum(invs_per_method)
    invs_per_method = invs_per_method[1:min(n_rows, n_invs_total)]
    trees = trees[1:min(n_rows, n_invs_total)]
    trunc_msg = truncated_invs ? " (showing $n_rows functions) " : ""
    mgs_prefix = job_name == "" ? "" : "$job_name: "
    @info "$mgs_prefix$n_total_invalidations methods invalidated for $n_invs_total functions$trunc_msg"
    n_invalidations_percent = map(invs_per_method) do inv
        inv_perc = inv / sum_invs
        Int(round(inv_perc*100, digits = 0))
    end
    meth_name = map(trees) do inv
        "$(inv.method.name)"
    end
    fileinfo = map(trees) do inv
        "$(process_filename(string(inv.method.file))):$(inv.method.line)"
    end
    header = (
        ["<file name>:<line number>", "Function Name", "Invalidations", "Invalidations %"],
        ["", "", "", "(xᵢ/∑x)"],
    )
    table_data = hcat(
        fileinfo,
        meth_name,
        invs_per_method,
        n_invalidations_percent,
    )

    PrettyTables.pretty_table(
        table_data;
        header,
        formatters = PrettyTables.ft_printf("%s", 2:2),
        header_crayon = PrettyTables.crayon"yellow bold",
        subheader_crayon = PrettyTables.crayon"green bold",
        crop = :none,
        alignment = [:l, :c, :c, :c],
    )
end
