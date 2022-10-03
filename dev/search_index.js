var documenterSearchIndex = {"docs":
[{"location":"","page":"Home","title":"Home","text":"CurrentModule = ImplicitAD","category":"page"},{"location":"#ImplicitAD","page":"Home","title":"ImplicitAD","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Documentation for ImplicitAD.","category":"page"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"","page":"Home","title":"Home","text":"Modules = [ImplicitAD]","category":"page"},{"location":"#ImplicitAD.drdy_forward-Tuple{Any, Any, Any}","page":"Home","title":"ImplicitAD.drdy_forward","text":"compute Aij = ∂ri/∂y_j\n\n\n\n\n\n","category":"method"},{"location":"#ImplicitAD.implicit_function-Tuple{Any, Any, Any}","page":"Home","title":"ImplicitAD.implicit_function","text":"implicit_function(solve, residual, x; jvp=jvp_forward, vjp=vjp_reverse, drdx=nothing, drdy=drdy_forward, lsolve=linear_solve)\n\nMake implicit function AD compatible (specifically with ForwardDiff and ReverseDiff).\n\nArguments\n\nsolve::function: y = solve(x). Solve implicit function (where residual!(r, x, y) = 0, see below)\nresidual!::function: residual!(r, x, y). Set residual r, given input x and state y.\nx::vector{float}: evaluation point.\njvp::function: jvp(residual, x, y, v).  Compute Jacobian vector product b = B*v where Bij = ∂ri/∂x_j.  r = residual(x, y) (note explicit form.  Default leverages dual numbers in forward mode AD where Jacobian is not explicitly constructed.\nvjp::function: vjp(residual, x, y, v).  Compute vector Jacobian product c = B^T v = (v^T B)^T where Bij = ∂ri/∂x_j and return c  Default is reverse mode AD where Jacobian is not explicitly constructed.  Computes gradient of a scalar function.\ndrdx::function: drdx(residual, x, y).  Provide (or compute yourself): ∂ri/∂xj.  Not a required function. Default is nothing.  If provided, then jvp and jvp are ignored and explicitly multiplied against this provided Jacobian.\ndrdy::function: drdy(residual, x, y).  Provide (or compute yourself): ∂ri/∂yj.  Default is forward mode AD.\nlsolve::function: lsolve(A, b).  Linear solve A x = b  (where A is computed in drdy and b is computed in jvp, or it solves A^T x = c where c is computed in vjp).  Default is backslash operator.\n\n\n\n\n\n","category":"method"},{"location":"#ImplicitAD.implicit_linear_function-Tuple{Any, Any}","page":"Home","title":"ImplicitAD.implicit_linear_function","text":"implicit_linear_function(A, b; lsolve=linear_solve, fact=factorize)\n\nMake implicit function AD compatible (specifically with ForwardDiff and ReverseDiff). This version is for linear equations Ay = b\n\nArguments\n\nA::matrix, b::vector: y = A^-1 b\nlsolve::function: lsolve(A, b).  Linear solve A y = b\n\n\n\n\n\n","category":"method"},{"location":"#ImplicitAD.jvp_forward-Tuple{Any, Any, Any}","page":"Home","title":"ImplicitAD.jvp_forward","text":"Compute Jacobian vector product b = B*v where Bij = ∂ri/∂x_j This takes in the dual directly since it is already formed that way.\n\n\n\n\n\n","category":"method"},{"location":"#ImplicitAD.jvp_provide-NTuple{5, Any}","page":"Home","title":"ImplicitAD.jvp_provide","text":"internal convenience method for when user can provide drdx\n\n\n\n\n\n","category":"method"},{"location":"#ImplicitAD.linear_solve-Tuple{Any, Any}","page":"Home","title":"ImplicitAD.linear_solve","text":"Linear solve A x = b  (where A is computed in drdy and b is computed in jvp).\n\n\n\n\n\n","category":"method"},{"location":"#ImplicitAD.pack_dual-Tuple{AbstractFloat, Any, Any}","page":"Home","title":"ImplicitAD.pack_dual","text":"Create a ForwardDiff Dual with value yv, derivatives dy, and Dual type T\n\n\n\n\n\n","category":"method"},{"location":"#ImplicitAD.unpack_dual-Tuple{Any}","page":"Home","title":"ImplicitAD.unpack_dual","text":"unpack ForwardDiff Dual return value and derivative.\n\n\n\n\n\n","category":"method"},{"location":"#ImplicitAD.vjp_provide-NTuple{5, Any}","page":"Home","title":"ImplicitAD.vjp_provide","text":"internal convenience method for when user can provide drdx\n\n\n\n\n\n","category":"method"},{"location":"#ImplicitAD.vjp_reverse-NTuple{4, Any}","page":"Home","title":"ImplicitAD.vjp_reverse","text":"Compute vector Jacobian product c = B^T v = (v^T B)^T where Bij = ∂ri/∂x_j and return c\n\n\n\n\n\n","category":"method"}]
}
