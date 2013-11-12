function quadToStr(a::AffExpr)
  # Hack...
  return affToStr(a)
end


function solve(rm::RobustModel, preferred_mode=:Cut)

  # MASTER PROBLEM
  master = Model()
  master.objSense  = rm.objSense
  master.obj       = QuadExpr(Variable[],Variable[],Float64[],rm.obj)  # For now, only certain aff obj
  master.linconstr = rm.certainconstr
  master.numCols   = rm.numCols
  master.colNames  = rm.colNames
  master.colLower  = rm.colLower
  master.colUpper  = rm.colUpper
  master.colCat    = rm.colCat
  mastervars       = [Variable(master, i) for i = 1:rm.numCols]

  # As a more general question, need to figure out a principled way of putting
  # box around original solution, or doing something when original solution is unbounded.
  for j in 1:master.numCols
    master.colLower[j] = max(master.colLower[j], -10000)
    master.colUpper[j] = min(master.colUpper[j], +10000)
  end

  # Query the abilities of all the wranglers so we can figure out what we'll do with them
  wrangler_modes = Symbol[]
  for c in rm.uncertainconstr
    support = querySupport(c.wrangler)
    sel_mode = (support == :Both) ? preferred_mode : support
    push!(wrangler_modes, sel_mode)
    setup!(c.wrangler, sel_mode, c, rm)
  end

  # For wranglers that want/have to reformulate, process them now
  for i = 1:length(wrangler_modes)
    if wrangler_modes[i] == :Reform
      generateReform(rm.uncertainconstr.wrangler, rm, master)
    end
  end

  # Begin da loop
  #while true
  for iter = 1:2
    # Solve master
    master_status = solve(master)
    #println("Solved master")
    #println("CURRENT MASTER")
    #println(master)
    #println("END MASTER")
    #println("Master solution:")
    #println(master.colVal)

    # Generate cuts
    for i = 1:length(wrangler_modes)
      if wrangler_modes[i] == :Cut
        generateCut(rm.uncertainconstr[i].wrangler, master)
      end
    end
  end

  # Return solution
  rm.colVal = master.colVal
  rm.objVal = master.objVal
end
