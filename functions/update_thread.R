# File: update_thread.R
# I've updated this code to use the newer "structured output" feature of the API

# Define the barter schema for structured output
barter_schema <- list(
  name = "barter_response",
  schema = list(
    type = "object",
    properties = list(
      message = list(type = "string"),
      quantity_good_x = list(type = "number"),
      quantity_good_y = list(type = "number")
    ),
    required = c("message", "quantity_good_x", "quantity_good_y"),
    additionalProperties = FALSE
  ),
  strict = TRUE
)

update_thread_response <- function(connection, new_message, turn, model, 
                                   # temperature  = max(min(rnorm(1, mean = 0.25, 
                                   #                                   sd = 0.1), 
                                   #                        1), 0), 
                                   top_p  = 1, 
                                   n      = 1, 
                                   stream = FALSE, 
                                   #max_tokens          = 4096, 
                                   presence_penalty    = 0, 
                                   frequency_penalty   = 0, 
                                   #logit_bias          = NULL, 
                                   openai_api_key      = MY_KEY,
                                   utility_fn          = NULL,
                                   openai_organization = NULL) {
  
  # Append the new user message to the conversation history
  connection$messages <- append(connection$messages, list(list(role = "user", 
                                                               content = new_message)))
  ifelse(new_message == msg, "Starting", msg)
  # Logging the user message
  #log_message(sender = connection$id, goods_held = connection$goods_held, turn = turn, 
  #            message = new_message, utilityfn = utility_fn)
  
  # Retry mechanism for rate limit handling
  max_retries <- 5
  retries     <- 0
  repeat {
    response <- tryCatch({
      # Make the API call with structured output
      req_body <- list(
        model = model,
        messages = connection$messages,
        #temperature = temperature,
        top_p = top_p,
        n = n,
        stream = stream,
        #max_tokens = max_tokens,
        presence_penalty = presence_penalty,
        frequency_penalty = frequency_penalty,
        #logit_bias = logit_bias,
        response_format = list(
          type = "json_schema",
          json_schema = barter_schema
        )
      )
      
      # Perform the API call
      res <- POST(
        url = "https://api.openai.com/v1/chat/completions",
        add_headers(Authorization = paste("Bearer", openai_api_key)),
        content_type_json(),
        body = toJSON(req_body, auto_unbox = TRUE)
      )
      
      if (http_error(res)) {
        stop("API request failed: ", status_code(res), "\n", content(res, "text"))
      }
      
      # Parse the response
      resp_content <- content(res, as = "text", encoding = "UTF-8")
      fromJSON(resp_content)
      
    }, error = function(e) {
      # Handle errors as before
      if (grepl("Rate limit reached", e$message) || grepl("invalid Unicode output", e$message)) {
        message <- e$message
        if (grepl("Rate limit reached", e$message)) {
          wait_time <- as.numeric(sub(".*Please try again in ([0-9\\.]+)s.*", "\\1", message))
          cat("Rate limit reached. Retrying in", wait_time, "seconds...\n")
          Sys.sleep(wait_time)
        } else {
          cat("Invalid Unicode output detected. Retrying with lower temperature...\n")
          #temperature <- max(temperature - 0.2, 0) # Reduce temperature
        }
        retries <- retries + 1
        if (retries >= max_retries) {
          stop("Maximum retries reached. Exiting.")
        }
        NULL
      } else if (grepl("HTTP/2 stream 9 was not closed cleanly", e$message)) {
        cat("HTTP/2 stream issue detected. Retrying...\n")
        retries <- retries + 1
        Sys.sleep(1) # Brief pause before retrying
        if (retries >= max_retries) {
          stop("Maximum retries reached. Exiting.")
        }
        NULL
      } else {
        stop(e)
      }
    })
    
    if (!is.null(response)) {
      break
    }
  }
  
  # Check if the API returned a refusal (safe completion)
  if (!is.null(response$refusal)) {
    stop("Model refusal: ", response$refusal)
  }
  
  # Extract the assistant's reply from the response
  reply <- response$choices$message$content
  reply <- fromJSON(reply)
  
  # Update goods_held using structured output
  connection$goods_held <- paste(reply$quantity_good_x, "units of Good X and", 
                                 reply$quantity_good_y, "units of Good Y")
  
  # Append the assistant's reply to the conversation history
  connection$messages <- append(connection$messages, 
                                list(list(role = "assistant", 
                                          content = reply$message)))
  
  # Logging the assistant message
  log_message(sender     = connection$id, 
              goods_held = connection$goods_held, 
              turn       = turn, 
              message    = reply$message,
              utilityfn  = utility_fn)
  
  return(connection)
}
