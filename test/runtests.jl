# Copyright (c) 2020-2024, Bank of Canada
# All rights reserved.

using Test
using FAME

using TimeSeriesEcon

if FAME.chli.lib === nothing

    @error "FAME CHLI library not found"
    exit()

end

@testset "workspaces" begin
    w = Workspace(; a=1, b=TSeries(2020Q1, randn(10)),
        s=MVTSeries(2020M1, (:q, :p), randn(24, 2)),
        c=Workspace(; alpha=0.1, beta=0.8,
            n=Workspace(; s="Hello World")
        ))
    writefame("data.db", w)
    @test length(listdb("data.db")) == 7

    tmp = readfame("data.db")
    @test tmp isa Workspace && length(tmp) == 7
    @test issubset(keys(tmp), (:a, :b, :c_alpha, :c_beta, :c_n_s, :s_p, :s_q))

    tmp = readfame("data.db", "s?")
    @test tmp isa Workspace && length(tmp) == 2
    @test issubset(keys(tmp), (:s_p, :s_q))

    tmp = readfame("data.db", "s?", prefix="s")
    @test tmp isa Workspace && length(tmp) == 2
    @test issubset(keys(tmp), (:p, :q))

    tmp = readfame("data.db", "c?", collect="c")
    @test tmp isa Workspace && length(tmp) == 1
    @test issubset(keys(tmp), (:c,))
    @test tmp.c isa Workspace && length(tmp.c) == 3
    @test issubset(keys(tmp.c), (:alpha, :beta, :n_s))

    tmp = readfame("data.db", collect=["c" => ["n"], "s"])
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

frequency_to_name(F::Type) = lowercase(replace(replace(String(Symbol(F)), "{" => ""), "}" => ""))
@testset "writing and reading all frequencies" begin
    frequencies = [
        Daily,
        BDaily,
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
        HalfYearly,
        HalfYearly{1},
        HalfYearly{2},
        HalfYearly{3},
        HalfYearly{4},
        HalfYearly{5},
        # HalfYearly{6},
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
        subcounter = 1
        for i in 1:500
            year = rand(collect(1970:2030))
            month = rand(collect(1:12))
            day = rand(collect(1:28))
            if F == Daily
                t = TSeries(daily("$year-$month-$day"), collect(1:800))
            elseif F <: BDaily
                t = TSeries(bdaily("$year-$month-$day", bias=:previous), collect(1:600))
            elseif F <: Weekly
                t = TSeries(weekly("$year-$month-$day", TimeSeriesEcon.endperiod(F)), collect(1:200))
                # t = TSeries(fconvert(F, daily("$year-$month-$day")), collect(1:200))
            elseif F <: Yearly
                t = TSeries(MIT{F}(year), collect(1:40))
            elseif F <: HalfYearly
                t = TSeries(MIT{F}(year), collect(1:40))
            elseif F <: Monthly
                t = TSeries(MIT{F}(year * 12 + month), collect(1:40))
            elseif F <: Quarterly
                t = TSeries(MIT{F}(year * 4 + month), collect(1:40))
            end

            db_write[Symbol("t_$(frequency_to_name(F))_$subcounter")] = t
            db_write[Symbol("mit_$(frequency_to_name(F))_$subcounter")] = t.firstdate
            subcounter += 1
        end
        counter += 1
    end
    writefame("db_write.db", db_write)
    db_read = readfame(joinpath(pwd(), "db_write.db"))
    @test compare(db_write, db_read, quiet=true)

    rm("db_write.db")
end

@testset "empty tseries" begin
    FAME.init_chli()
    test_db = workdb()

    w = Workspace(;
        t1=TSeries(1995Q1),
        t2=TSeries(Float32, 1993Q3),
        t3=TSeries(Bool, 1996Q2),
        t4=TSeries(1996Q2, Vector{Bool}([true, false, true])),
        t5=TSeries(MIT{Yearly{12}}, 1998Q3),
        t6=TSeries(1997Q1, Vector{MIT{Yearly{12}}}([2022Y, 2023Y]))
    )
    writefame(test_db, w)
    @test length(listdb(test_db)) == 6

    wr = readfame(test_db)

    @test isquarterly(wr.t1) == true
    @test isquarterly(wr.t2) == true
    @test isquarterly(wr.t3) == true
    @test isquarterly(wr.t4) == true
    @test isquarterly(wr.t5) == true
    @test isquarterly(wr.t6) == true
    @test eltype(wr.t1) <: Float64
    @test eltype(wr.t2) <: Float32
    @test eltype(wr.t3) <: Bool
    @test eltype(wr.t4) <: Bool
    @test eltype(wr.t5) <: MIT{Yearly{12}}
    @test eltype(wr.t6) <: MIT{Yearly{12}}

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

end

@testset "tuples" begin
    data = Workspace(;
        svec=["qmazing", "qmazing", "p", "phantastic"],
        stup=("qmazing", "qmazing", "p", "phantastic")
    )
    rm("test.db", force=true)
    try
        writefame("test.db", data)
        data_r = readfame("test.db")
        @test data_r.svec == data.svec
        # string tuples are read into string vectors
        @test data_r.stup == String[data.stup...]
    finally
        rm("test.db", force=true)
    end
end
