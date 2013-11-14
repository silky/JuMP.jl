function quadToStr(a::AffExpr)
  # Hack...
  return affToStr(a)
end


function solve(rm::RobustModel;preferred_mode=:Cut,report=false)

  # Create master problem
  start_time = time()
  master = Model(solver=rm.solver)
  master.objSense  = rm.objSense
  master.obj       = QuadExpr(Variable[],Variable[],Float64[],rm.obj)  # For now, only certain aff obj
  master.linconstr = rm.certainconstr
  master.numCols   = rm.numCols
  master.colNames  = rm.colNames
  master.colLower  = rm.colLower
  master.colUpper  = rm.colUpper
  master.colCat    = rm.colCat
  mastervars       = [Variable(master, i) for i = 1:rm.numCols]
  master_init_time = time() - start_time

  # As a more general question, need to figure out a principled way of putting
  # box around original solution, or doing something when original solution is unbounded.
  for j in 1:master.numCols
    master.colLower[j] = max(master.colLower[j], -10000)
    master.colUpper[j] = min(master.colUpper[j], +10000)
  end

  # Query the abilities of all the wranglers so we can figure out what we'll do with them
  wrangler_setup_time = time()
  wrangler_modes = Symbol[]
  for c in rm.uncertainconstr
    support = querySupport(c.wrangler)
    sel_mode = (support == :Both) ? preferred_mode : support
    push!(wrangler_modes, sel_mode)
    setup!(c.wrangler, sel_mode, c, rm)
  end
  wrangler_setup_time = time() - wrangler_setup_time

  # For wranglers that want/have to reformulate, process them now
  reform_time = time()
  reformed_cons = 0
  for i = 1:length(wrangler_modes)
    if wrangler_modes[i] == :Reform
      generateReform(rm.uncertainconstr.wrangler, rm, master)
      reformed_cons += 1
    end
  end
  reform_time = time() - reform_time

  # Begin da loop
  cutting_rounds = 0
  cuts_added = 0
  master_time = 0
  cut_time = 0
  while true
    cutting_rounds += 1
    
    # Solve master
    tic()
    master_status = solve(master)
    master_time += toq()

    # Generate cuts
    cut_added = false
    tic()
    for i = 1:length(wrangler_modes)
      if wrangler_modes[i] == :Cut
        if generateCut(rm.uncertainconstr[i].wrangler, master)
          cut_added = true
          cuts_added += 1
        end
      end
    end
    cut_time += toq()

    if !cut_added
      break
    end
  end

  # Return solution
  total_time = time() - start_time
  rm.colVal = master.colVal
  rm.objVal = master.objVal

  # Report if request
  if report
    println("Solution report")
    println("Prefered method: $(preferred_mode==:Cut ? "Cuts" : "Reformulations")")
    println("Uncertain Constraints:")
    println("  Reformulated     $reformed_cons")
    println("  Cutting plane    $(length(rm.uncertainconstr) - reformed_cons)")
    println("  Total            $(length(rm.uncertainconstr))")
    println("Cutting rounds:  $cutting_rounds")
    println("Total cuts:      $cuts_added")
    println("Overall time:    $total_time")
    println("  Master init      $master_init_time")
    println("  Wrangler setup   $wrangler_setup_time")
    println("  Reformulation    $reform_time")
    println("  Master solve     $master_time")
    println("  Cut solve&add    $cut_time")
  end

end
