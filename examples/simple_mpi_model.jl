using Pkg
Pkg.activate((@__DIR__)*"/..")

using Plasmo
using MPI
using PipsNLP

MPI.Init()

comm = MPI.COMM_WORLD
ncores = MPI.Comm_size(comm)
rank = MPI.Comm_rank(comm)

#8 scenarios
Ns = 8

#scenario per processor (SPP)
SPP = round(Int, floor(Ns/ncores))

function create_simple_model(d)
    node = OptiNode()
    @variable(node, 0<=p<=10, start=5)
    @variable(node, u)
    @variable(node, x)
    @constraint(node, x >= p)
    @constraint(node, p + u == d)
    return node
end

#Setup processor information
demand = rand(Ns)*10
graph = OptiGraph()

first_stage = @optinode(graph)
@variable(first_stage,0 <= x <= 8)
@objective(first_stage,Min,x)

owned = []
s = 1

#subgraph contains the scenarios
subgraph = OptiGraph()
add_subgraph!(graph,subgraph)
for j in 1:Ns
    global s
    if round(Int, floor((s-1)/SPP)) == rank
        push!(owned, s)
        node = create_simple_model(demand[j])
        add_node!(subgraph,node)

        #connect children and parent variables
        @linkconstraint(graph, first_stage[:x] == node[:x])

        #reconstruct second stage objective
        @objective(node,Min,1/Ns*(node[:p] + 3*node[:u]))
    else # create a ghost node (empty model)
        node = add_node!(subgraph)
    end
    s = s + 1
end

#create a link constraint between the subproblems (PIPS-NLP supports this kind of constraint)
@linkconstraint(graph, (1/Ns)*sum(getnode(subgraph,s)[:p] for s in owned) == 8)
PipsNLP.pipsnlp_solve(graph)

MPI.Finalize()
