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
    writefame(workdb(), Workspace(; pr, nu))
    for n in ("pr", "nu")
        let b = IOBuffer()
            fame(b, "disp $n")
            seek(b, 0)
            @test sum(Base.Fix1(occursin, r"20:4\s+NC"), readlines(b)) == 1
        end
    end
end

@testset "writing and reading all frequencies" begin
    frequencies = [
        Daily,
        BusinessDaily,
        Weekly,
        Weekly{1},
        Weekly{2},
        Weekly{3},
        Weekly{4},
        Weekly{5},
        Weekly{6},
        # Weekly{7}
        Monthly,
        Quarterly,
        Quarterly{1},
        Quarterly{2},
        # Quarterly{3},
        Yearly,
        Yearly{1},
        Yearly{2},
        Yearly{3},
        Yearly{4},
        Yearly{5},
        Yearly{6},
        Yearly{7},
        Yearly{8},
        Yearly{9},
        Yearly{10},
        Yearly{11},
        # Yearly{12}
    ]
    counter = 1
    db_write = Workspace()
    for F in frequencies
        t2 = nothing
        if F == Daily
            t = TSeries(daily("2022-01-03"), collect(1:800))
        elseif F <: CalendarFrequency 
            t = TSeries(fconvert(F, daily("2000-06-01")), collect(1:200))
            t2 = TSeries(fconvert(F, daily("1975-01-01")), collect(1:200))
        elseif F <: Yearly
            t = TSeries(MIT{F}(2000), collect(1:40))
        elseif F <: Monthly
            t = TSeries(MIT{F}(2000*12), collect(1:40))
        elseif F <: Quarterly
            t = TSeries(MIT{F}(2000*4), collect(1:40))
        end

        db_write[Symbol("t$(counter)")] = t
        db_write[Symbol("mit$(counter)")] = t.firstdate
        counter += 1
        if t2 !== nothing
            db_write[Symbol("t$(counter)_early")] = t2
            db_write[Symbol("mitt$(counter)_early")] = t2.firstdate
        end
    end
    writefame("db_write.db", db_write)
    db_read = readfame(joinpath(pwd(), "db_write.db"));
    @test compare(db_write, db_read) == true

    rm("db_write.db")
end
