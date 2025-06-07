# File: exchange_messages.R
exchange_messages <- function(conn1, conn2, initial_message, max_turns = 10) {
  turn <- 1
  conn1 <- update_thread_response(conn1, initial_message, turn, 
                                  utility_fn = conn1$utility_fn, model = ai_model)
  conn2 <- update_thread_response(conn2, conn1$messages[[3]]$content, turn, 
                                  utility_fn = conn2$utility_fn, model = ai_model)
  
  for (i in seq_len(max_turns)) {
    cat("Turn", i, "...\n")
    turn  <- i + 1
    conn1 <- update_thread_response(conn1, conn2$messages[[length(conn2$messages)]]$content, 
                                    turn, utility_fn = conn1$utilityfn, model = ai_model)
    conn2 <- update_thread_response(conn2, conn1$messages[[length(conn1$messages)]]$content, 
                                    turn, utility_fn = conn2$utilityfn, model = ai_model)
    
    last_msg_conn1 <- conn1$messages[[length(conn1$messages)]]$content
    last_msg_conn2 <- conn2$messages[[length(conn2$messages)]]$content
    
    if (grepl("UTILITY", last_msg_conn1, ignore.case = TRUE) || grepl("UTILITY", last_msg_conn2, ignore.case = TRUE)) {
      if (grepl("UTILITY", last_msg_conn1, ignore.case = TRUE)) {
        consensus <- last_msg_conn1
      } else {
        consensus <- last_msg_conn2
      }
      return(list(conn1 = conn1, conn2 = conn2, consensus = consensus))
    }
    
  }
  
  consensus <- NA
  return(list(conn1 = conn1, conn2 = conn2, consensus = consensus))
}