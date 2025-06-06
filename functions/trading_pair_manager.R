# File: trading_pair_manager.R
trading_pair_manager <- function(num_connections, max_turns = 20) {
  connections <- create_openai_connections(num_connections)
  results     <- data.frame(pair_id = integer(), consensus = character(), stringsAsFactors = FALSE)
  
  for (i in seq_along(connections)) {
    assign(paste0("utilfn_agent_",i), connections[[i]]$utility_fn)
  }
  
  num_pairs <- floor(num_connections / 2)
  for (i in seq_len(num_pairs)) {
    conn1 <- connections[[2 * i - 1]]
    conn2 <- connections[[2 * i]]
    
    result <- exchange_messages_until_consensus(conn1, 
                                                conn2, 
                                                msg,#"Read the original system message and begin trading.", 
                                                max_turns  = max_turns)
    
    results <- results %>% 
      add_row(pair_id = i, consensus = result$consensus)
    
    cat("Pair", i, "consensus:", result$consensus, "\n")
  }
  
  if (num_connections %% 2 == 1) {
    # Handle the odd connection separately if needed
    last_conn <- connections[[num_connections]]
    cat("Connection", num_connections, "has no pair and is not included in the test.\n")
  }
  
  save_log()
  return("Done.")
}