# Copyright (c) 2020-2021, Bank of Canada
# All rights reserved.


### Open Database

### Work database
"""
    workdb()

Return a [`FameDatabase`](@ref) instance for the work database. 

Since the work database can be open only once, we create an instance the first
time and return the existing instance each subsequent time.
"""
function workdb end
export workdb

function cfmopwk()
    dbkey = Ref{Cint}(-1)
    @cfm_call_check(cfmopwk, (Ref{Cint},), dbkey)
    return dbkey[]
end

function workdb()
    global chli
    if !isopen(chli.workdb[])
        chli.workdb[] = FameDatabase(cfmopwk(), "WORK", :update)
    end
    return chli.workdb[]
end

function workdb(F::Function)
    db = workdb()
    try
        F(db)
    finally
        closedb!(db)
    end
end

### Open database

"""
    opendb(dbname, [mode])

Open a FAME database and return an instance of [`FameDatabase`](@ref) for it.

`dbname` can be a path to a .db file or a string specifying a database over a
remote connection in the following format.

    "[<tcp_port>@]<host> [<username> [<password>] ] <db>"

`mode` can be an integer (consult the CHLI help), or a `Symbol`. Valid modes
include `:readonly`, `:create`, `:overwrite`, `:update`, `:shared`, `:write`,
`:direct_write`.
"""
function opendb end
export opendb

function cfmopdb(dbname::String, mode::Int32)
    dbkey = Ref{Cint}(-1)
    @cfm_call_check(cfmopdb, (Ref{Cint}, Cstring, Cint), dbkey, dbname, mode)
    return dbkey[]
end

opendb(dbname::String, mode=:readonly) = 
    FameDatabase(cfmopdb(dbname, val_to_int(mode, access_mode)), dbname, mode)

function opendb(F::Function, args...)
    db = opendb(args...)
    try
        F(db)
    finally
        closedb!(db)
    end
end

### Post database

export postdb
"""
    postdb(db::FameDatabase)

Post the given FAME database. If you've made any updates to the database you
must post it before closing, otherwise all your changes will be lost.
"""
postdb(db::FameDatabase) = @cfm_call_check(cfmpodb, (Cint,), db.key)

### Close database

export closedb!

cfmcldb(dbkey::Int32) = @cfm_call_check(cfmcldb, (Cint,), dbkey)

"""
    closedb!(db::FameDatabase)

Close the given FAME database.
"""
function closedb!(db::FameDatabase)
    cfmcldb(db.key)
    ind = indexin([db], chli.opendb)[1]
    if ind !== nothing
        deleteat!(chli.opendb, ind)
    else
        @warn "Closing untracked database. " (key = db.key, name = db.name, mode = db.mode)
    end
    db.key = -1
    return db
end

