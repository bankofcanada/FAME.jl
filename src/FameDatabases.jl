

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

`mode` can be an integer code (consult the CHLI help), a string or an
[`AccessMode`](@ref).
"""
function opendb end
export opendb

function cfmopdb(dbname::String, mode::Int32)
    dbkey = Ref{Cint}(-1)
    @cfm_call_check(cfmopdb, (Ref{Cint}, Cstring, Cint), dbkey, dbname, mode)
    return dbkey[]
end

@inline opendb(dbname::String, mode=:readonly) = (
    FameDatabase(cfmopdb(dbname, val_to_int(mode, access_mode)), dbname, mode)
) 


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

Post database. If you've made any updates to the database you must post it
before closing. Othewise all your changes will be lost.
"""
@inline postdb(db::FameDatabase) = @cfm_call_check(cfmpodb, (Cint,), db.key)

### Close database

export closedb!

@inline cfmcldb(dbkey::Int32) = @cfm_call_check(cfmcldb, (Cint,), dbkey)

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

### List database

export listdb

"""
    item_option(name, values...)

Set ITEM option. These are used when matching a wildcard to database objects.
Option names include "CLASS", "TYPE", "FREQUENCY", "ALIAS".

When the `values` argument is not given, it defaults to "ON". Otherwise `values`
should be strings and indicate which ITEMs are to be turned on.

"""
function item_option end

function item_option(name::String, values::AbstractString...)
    uname = uppercase(strip(name))
    if isempty(values) || (length(values) == 1 && isempty(strip(values[1])))
        @cfm_call_check(cfmsopt, (Cstring, Cstring), "ITEM $uname", "ON")
        return
    end
    @cfm_call_check(cfmsopt, (Cstring, Cstring), "ITEM $uname", "OFF")
    for val in values
        uval = uppercase(strip(val))
        try
            @cfm_call_check(cfmsopt, (Cstring, Cstring), "ITEM $uname $uval", "ON")
        catch e
            e isa HLIError && @error "Bad $(uname) $(uval)."
            rethrow()
        end
    end
end


"""
    listdb(db::FameDatabase, [wc; filters...])

List objects in the database that match the given wildcard and filters.

The wildcard `wc` is a string containing wildcatd characters. 
'^' matches any one character while '?' matches any zero or more characters.

The filters:
  * `alias::Bool` - whether or not to match alias names. 
  * `class::String` - which class of object to match. Multiple classes can be
    given in a comma-separated string, e.g., `class="SERIES,SCALAR"`.
  * `type::String` - same as `class` but for the type of the object
    ("NUMERIC,PRECISION").
  * `freq::String` - same as `class` but for the frequency of the object.

"""
function listdb(db::FameDatabase, wildcard::String = "?";
    alias::Bool = true, class::String = "", type::String = "", freq::String = "")

    @cfm_call_check(cfmsopt, (Cstring, Cstring), "ITEM ALIAS", alias ? "ON" : "OFF")
    item_option("CLASS", split(class, ",")...)
    item_option("TYPE", split(type, ",")...)
    item_option("FREQUENCY", split(freq, ",")...)

    wc_key = Ref{Cint}(-1)
    @fame_call_check(fame_init_wildcard,
        (Cint, Ref{Cint}, Cstring, Cint, Cstring),
        db.key, wc_key, wildcard, 0, C_NULL)
    # ob = Vector{QuickInfo}()
    try
        while true
            name = repeat(" ", 101)
            cl = Ref{Cint}(-1)
            ty = Ref{Cint}(-1)
            fr = Ref{Cint}(-1)
            fp = Ref{Clonglong}(-1)
            lp = Ref{Clonglong}(-1)
            status = @fame_call(fame_get_next_wildcard,
                (Cint, Cstring, Ref{Cint}, Ref{Cint}, Ref{Cint}, Ref{Clonglong}, Ref{Clonglong}, Cint, Ref{Cint}),
                wc_key.x, name, cl, ty, fr, fp, lp, length(name) - 1, C_NULL)
            if status == HNOOBJ
                break
            elseif status == HTRUNC
                println("Object name too long and truncated $name")
            else
                check_status(status)
            end
            # FAME pads the string with \0 on the right to the length we gave.
            name = strip(name, '\0')
            println(name, " => ", cl[], " ", ty[], " ", fr[], " ", fp[], " ", lp[])
            # push!(ob, QuickInfo(name, cl[], ty[], fr[], FameIndex(fp[]), FameIndex(lp[])))
        end
    finally
        @fame_call(fame_free_wildcard, (Cint,), wc_key[])
    end
    # return ob
end



###

# export savedb
# function savedb(db::FameDatabase,data::Dict)
#     listnames = collect(keys(data));
#     for (k,v) in data
#         if isfameobject(v) 
#             try
#                 fame_write(db, v)
#             catch
#                 @error "Failed to write $k to database."
#                 rethrow()
#             end
#         else
#             @warn "Element $(k) is not a FameObject; not written."
#         end
#     end
# end

