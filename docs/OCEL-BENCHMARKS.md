# OCEL and peer benchmarks

`OCEL.build` turns imported attributes into object types (case, order/customer/
invoice/employee). Events link to every object they name, and the UI reports
object counts, multi-object events and pairwise interactions. The object
dimensions are chosen by the user; no object identity is invented.

`PeerBenchmarks.library` is a small **illustrative** cohort set. It compares the
current median cycle and rework against a labelled synthetic cohort. It is not a
vendor benchmark and must not be presented as external truth; replace it with a
governed benchmark feed before customer use.
