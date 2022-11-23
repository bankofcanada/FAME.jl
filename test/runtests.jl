# Copyright (c) 2020-2022, Bank of Canada
# All rights reserved.

using Test
using FAME

using TimeSeriesEcon

if FAME.chli.lib === nothing

    @error "FAME CHLI library not found"
    exit()

end

@testset "workspaces" begin
    w = Workspace(; a = 1, b = TSeries(2020Q1, randn(10)),
        s = MVTSeries(2020M1, (:q, :p), randn(24, 2)),
        c = Workspace(; alpha = 0.1, beta = 0.8,
            n = Workspace(; s = "Hello World")
        ))
    writefame("data.db", w)
    @test length(listdb("data.db")) == 7

    tmp = readfame("data.db")
    @test tmp isa Workspace && length(tmp) == 7
    @test issubset(keys(tmp), (:a, :b, :c_alpha, :c_beta, :c_n_s, :s_p, :s_q))

    tmp = readfame("data.db", "s?")
    @test tmp isa Workspace && length(tmp) == 2
    @test issubset(keys(tmp), (:s_p, :s_q))

    tmp = readfame("data.db", "s?", prefix = "s")
    @test tmp isa Workspace && length(tmp) == 2
    @test issubset(keys(tmp), (:p, :q))

    tmp = readfame("data.db", "c?", collect = "c")
    @test tmp isa Workspace && length(tmp) == 1
    @test issubset(keys(tmp), (:c,))
    @test tmp.c isa Workspace && length(tmp.c) == 3
    @test issubset(keys(tmp.c), (:alpha, :beta, :n_s))

    tmp = readfame("data.db", collect = ["c" => ["n"], "s"])
    @test tmp isa Workspace && length(tmp) == 4
    @test issubset(keys(tmp), (:a, :b, :c, :s))
    @test tmp.c isa Workspace && length(tmp.c) == 3
    @test issubset(keys(tmp.c), (:alpha, :beta, :n))
    @test tmp.c.n isa Workspace && length(tmp.c.n) == 1
    @test issubset(keys(tmp.c.n), (:s,))
    @test tmp.s isa Workspace && length(tmp.s) == 2
    @test issubset(keys(tmp.s), (:p, :q))

    rm("data.db")
end

@testset "missing" begin
    FAME.init_chli()
    pr = TSeries(2020Q1, randn(Float64, 8))
    pr[2020Q4] = NaN
    nu = TSeries(2020Q1, randn(Float32, 8))
    nu[2020Q4] = NaN
    test_db = workdb()
    writefame(test_db, Workspace(; pr, nu))
    for n in ("pr", "nu")
        let b = IOBuffer()
            fame(b, "disp $n")
            seek(b, 0)
            @test sum(Base.Fix1(occursin, r"20:4\s+NC"), readlines(b)) == 1
        end
    end
end

@testset "empty tseries" begin
    w = Workspace(; 
        t1 = TSeries(1995Q1),
        t2 = TSeries(Float32, 1993Q3),
        t3 = TSeries(Bool, 1996Q2),
        t4 = TSeries(1996Q2, Vector{Bool}([true, false, true])),
        t5 = TSeries(MIT{Yearly}, 1998Q3),
        t6 = TSeries(1997Q1, Vector{MIT{Yearly}}([2022Y, 2023Y]))
    )
    writefame("empty_series_test.db", w)
    @test length(listdb("empty_series_test.db")) == 6

    wr = readfame("empty_series_test.db")
   
    @test typeof(wr.t1) == TSeries{Quarterly, Float64, Vector{Float64}}
    @test typeof(wr.t2) == TSeries{Quarterly, Float32, Vector{Float32}}
    @test typeof(wr.t3) == TSeries{Quarterly, Bool, Vector{Bool}}
    @test typeof(wr.t4) == TSeries{Quarterly, Bool, Vector{Bool}}
    @test typeof(wr.t5) == TSeries{Quarterly, MIT{Yearly}, Vector{MIT{Yearly}}}
    @test typeof(wr.t6) == TSeries{Quarterly, MIT{Yearly}, Vector{MIT{Yearly}}}
    @test wr.t1.firstdate == 1995Q1
    @test wr.t2.firstdate == 1993Q3
    @test wr.t3.firstdate == 1996Q2
    @test wr.t4.firstdate == 1996Q2
    @test wr.t5.firstdate == 1998Q3
    @test wr.t6.firstdate == 1997Q1
    @test length(wr.t1) == 0
    @test length(wr.t2) == 0
    @test length(wr.t3) == 0
    @test length(wr.t4) == 3
    @test length(wr.t5) == 0
    @test length(wr.t6) == 2
    @test wr.t4.values == [true, false, true]
    @test wr.t6.values == [2022Y, 2023Y]

    rm("empty_series_test.db")
end
