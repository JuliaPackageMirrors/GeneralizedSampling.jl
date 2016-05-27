using GeneralizedSampling
using Base.Test

println("Testing least squares solver...")

#=
Test the least squares solvers:
- Solution with Freq2Wave and the collected version should be identical.
- When sampling from a scaling function used in the Freq2Wave type, the solution should be a unit vector.
- A linear combination of scaling functions should be reproduced exactly.
=#


# ------------------------------------------------------------
# Reconstruct unit vector

function unit(length::Integer, entry::Integer)
	u = zeros(Complex{Float64}, length)
	u[entry] = one(Complex{Float64})
	return u
end

J = 3
M = 2^(J+1)
N = 2^J
xi = grid(M, 0.5)
wavename = "db2"
vm = van_moment(wavename)
T = freq2wave(xi, wavename, J)

for k = 1:N
	#= k = 7 =#
	if k <= vm
		F = FourDaubScaling(xi, vm, 'L', J)
		f = F[k,:]'
	elseif k > N-vm
		F = FourDaubScaling(xi, vm, 'R', J)
		# TODO: Include phaseshift in FourDaubScaling?
		f = cis( -2.0*pi*xi ) .* F[k-N+vm,:]'
	else
		f = FourDaubScaling(xi, vm, J, k-1)
	end
	y = T \ f

	#@show k, norm( y - unit(length(y),k) )
	@test_approx_eq_eps y unit(length(y),k) 1e-4
end

# ------------------------------------------------------------

begin
	J = 10
	M = 2^(J+2)
	N = 2^J

	# Uniform samples
	xi = grid(M, 0.5)
	TU = freq2wave(xi, "Haar", J)
	AU = collect(TU)

	b = rand(M)
	x0 = rand(N)

	x1 = AU \ b
	x2 = TU \ b

	#@show norm(x1 - x2, Inf)
	@test_approx_eq_eps x1 x2 1e-5


	# Non-uniform samples: Requires high M/N ratio 
	K = N/2
	xi = 2*K*rand(M) - K
	sort!(xi)
	TNU = freq2wave(xi, "Haar", J, K)
	ANU = collect(TNU)
	b = rand(M) + rand(M)*im

	# Avoid weighing b for ANU with "\"
	z0 = zeros(Complex{Float64}, N)
	z1 = cgnr( ANU, b, z0 )
	z2 = cgnr( TNU, b, z0 )

	#@show norm(z1 - z2, Inf)
	@test_approx_eq_eps z1 z2 1e-4
end

# 2D
#= begin =#
	J = 5
	M = 2^(J+1)

	# Uniform samples
	xi = grid((M,M), 0.5)
	TU = freq2wave(xi, "Haar", J)
	AU = collect(TU)
	b = rand(size(TU,1))

	x1 = AU \ b
	x2 = TU \ b

	#@show norm(x1 - vec(x2), Inf)
	@test_approx_eq_eps x1 x2 1e-5

	#=
	# Non-uniform samples: Requires high M/N ratio 
	K = N/2
	xi = 2*K*rand(M^2,2) - K
	TNU = freq2wave(xi, "Haar", J, K)
	ANU = collect(TNU)
	b = rand(M) + rand(M)*im

	# Avoid weighing b for ANU with "\"
	z0 = zeros(Complex{Float64}, N)
	z1 = cgnr( ANU, complex(b), z0 )
	z2 = cgnr( TNU, complex(b), z0 )

	# TODO: Non-uniform samples: Solutions are not from identical. Collected
	# matrix has *high* condition number
	=#
#= end =#

