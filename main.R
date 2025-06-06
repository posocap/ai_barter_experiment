######################################
# AI Utility Maximization via Barter #
#    Under Bounded Rationality       #
# https://posocap.com                #
# https://github.com/posocap         #
# First version: Fall 2023           #
# Last updated:  June 2025           #
######################################


# Params ------------------------------------------------------------------
# How many agents?
num_agents <- 2

# How many turns to allow before giving up?
max_turns <- 5

# AI model
ai_model <- "o3-mini" #"o4-mini-2025-04-16" "gpt-4o-mini"

# Libraries and Options ---------------------------------------------------
if (!require(pacman)) { install.packages("pacman"); library(pacman) }
p_load(openai, httr, jsonlite, lubridate, future, future.apply, dplyr,
       ggplot2)
plan(multisession)

set.seed(42)

MY_KEY <- Sys.getenv("OPENAI_API_KEY")

# Information Sharing -----------------------------------------------------
# If set to True (T) then partners may discuss their preferences, otherwise
#  only offer trades without sharing information.
discuss_preferences <- ifelse(T, "prompt.R", "prompt2.R") 

# C-D Utility Function Generator ------------------------------------------
# Randomly generate some Cobb-Douglas utility functions
source("util_gen.R")

# Endowment Generator -----------------------------------------------------
endowFn <- function() paste(sample(c(1:100), 1), "units of Good X and ", 
                            sample(c(1:100), 1), "units of Good Y")

# Make a vector of OpenAI instances ---------------------------------------
source(discuss_preferences)

create_openai_connections <- function(num_threads, sys_msg = msg) {
  connections <- vector("list", num_threads)
  for (i in seq_along(connections)) {
    goods_held <- endowFn()
    utilfn     <- utility_fn_generator(T)
    sys_msg_i  <- gsub("AAA", utilfn, sys_msg)
    sys_msg_i  <- gsub("BBB", goods_held, sys_msg_i)
    
    # Log the utility function
    log_message(sender = paste0("thread_", i), goods_held = goods_held, 
                turn = 0, message = "Initial setup", utilityfn = utilfn)
    
    # Create the connection
    connections[[i]] <- list(
      id         = paste0("thread_", i),
      messages   = list(list(role = "system", content = sys_msg_i)),
      goods_held = goods_held,
      utility_fn = utilfn
    )
  }
  return(connections)
}

# Logging setup -----------------------------------------------------------
log_messages <- data.frame(sender     = character(),
                           goods_held = character(),
                           turn       = integer(),
                           message    = character(),
                           utilityfn  = character(),
                           stringsAsFactors = FALSE)

log_message <- function(sender, goods_held, turn, message, utilityfn) {
  log_messages <<- log_messages %>%
    add_row(sender = sender, goods_held = goods_held, turn = turn, 
            message = message, utilityfn = utilityfn)
}

save_log <- function() {
  timestamp <- format(now(), "%Y%m%d_%H%M%S")
  saveRDS(log_messages, paste0("bargaining_log_", timestamp, ".rds"))
}

# Update thread response function -----------------------------------------
# API connections
source("update_thread.R")

# Bargaining Pairs --------------------------------------------------------
# Function to facilitate conversation until consensus is reached
source("exchange_messages_until_consensus.R")

# Function to manage multiple trading partners
source("trading_pair_manager.R")

# Run the Experiment ------------------------------------------------------
# How many AI individuals (should be even)
total_num_nodes <- num_agents
even            <- function(x) x %% 2 == 0

# Main execution
test_results    <- trading_pair_manager(ifelse(even(total_num_nodes), 
                                               total_num_nodes, 
                                               total_num_nodes + 1), 
                                        max_turns = max_turns)

# Append endowments to log
for(ai in unique(log_messages$sender)){
  endw <- log_messages$goods_held[min(as.numeric(rownames(
    log_messages[log_messages$sender==ai,])))]
  log_messages$endowment[log_messages$sender == ai] <- endw
}

print(test_results)
log_messages$sender <- gsub(log_messages$sender, pattern = "thread_", 
                            replacement = "Agent ")

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
saveRDS(test_results, paste0("test_results_", timestamp, "_", ai_model, ".RDS"))
saveRDS(log_messages, paste0("log_messages_information_sharing_", 
                             timestamp, "_", ai_model, ".RDS"))

# Append Utility ----------------------------------------------------------

# Parse out Good X and Good Y
quantity_good_x <- as.numeric(gsub(" units of Good X and.*", "", 
                                   log_messages$goods_held))
quantity_good_y <- as.numeric(gsub(".* and\\s*(\\d+)\\s*units of Good Y", 
                                   "\\1", log_messages$goods_held))

# Add the quantities to the log_messages
log_messages$X <- quantity_good_x
log_messages$Y <- quantity_good_y

# Assign an economy_id to each pair of agents
log_messages$economy_id <- ceiling(as.numeric(gsub("Agent ", "", log_messages$sender))/2)

for(s in unique(log_messages$sender)) {
  log_messages$utilityfn[log_messages$sender == s] <-
    log_messages$utilityfn[log_messages$turn   == 0 &
                             log_messages$sender == s]
}
# Calculate utility for each row
log_messages$utility <- NA

for (i in 1:nrow(log_messages)) {
  x_val <- ifelse(log_messages$X[i] > 0, log_messages$X[i], 0.01)
  y_val <- ifelse(log_messages$Y[i] > 0, log_messages$Y[i], 0.01)
  utility_function <- gsub("x", x_val, log_messages$utilityfn[i])
  utility_function <- gsub("y", y_val, utility_function)
  
  log_messages$utility[i] <- eval(parse(text = utility_function))
}

# Check the updated log_messages data frame
log_messages$endowment <- NULL
log_messages <- log_messages[order(log_messages$sender, log_messages$turn),]
view(log_messages)


# Utility Plot ------------------------------------------------------------
# Create a line plot of utility for each sender over turns
utility_plot <-
  ggplot(log_messages, aes(x = turn, 
                           y = utility, 
                           color = sender, 
                           group = sender)) +
    geom_line() +
    geom_point() +  # Optional: Add points to the lines for better visibility
    labs(title = "Utility for Each AI Agent Over Negotiation Rounds",
         x     = "Round Number",
         y     = "Utility") +
    theme_minimal() +
    theme(legend.title = element_blank())

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
ggsave(filename = paste0("utility_plot_", timestamp, "_", ai_model, ".png"), 
       plot = utility_plot, 
       width = 10, height = 6, dpi = 300)

# Data Validation ---------------------------------------------------------
log_messages[log_messages$turn %in% c(0, max(log_messages$turn)), ] %>%
  select(sender, turn, X, Y) %>%
  print()

# Total X and Y at Time=0
log_messages %>%
  filter(turn == 0) %>%
  summarise(total_X = sum(X), total_Y = sum(Y)) %>%
  print()

# Total X and Y at Time=Max
log_messages %>%
  filter(turn == max(log_messages$turn)) %>%
  summarise(total_X = sum(X), total_Y = sum(Y)) %>%
  print()
