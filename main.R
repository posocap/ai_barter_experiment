##############################################
#   AI Utility Maximization via Barter       #
#    Under Bounded Rationality Part I        #
# https://posocap.com                        #
# https://github.com/posocap                 #
# https://substack.com/@posocap/p-165322887  #
# First version: Fall 2023                   #
# Last updated:  June 2025                   #
##############################################


# Params ------------------------------------------------------------------
# How many agents?
num_agents <- 2

# How many turns to allow before giving up?
max_turns <- 5

ai_model <- "o3-mini"#"o4-mini-2025-04-16" #"gpt-4.1" #"o3-mini" #"o4-mini-2025-04-16" "gpt-4o-mini"

# Libraries and Options ---------------------------------------------------
if (!require(pacman)) { install.packages("pacman"); library(pacman) }
p_load(openai, httr, jsonlite, lubridate, future, future.apply, dplyr,
       ggplot2)
plan(multisession)

set.seed(42)

MY_KEY <- readLines("/openai_api_key.txt")

# Information Sharing -----------------------------------------------------
# If set to True (T) then partners may discuss their preferences freely, 
# otherwise not 
#  only offer trades without sharing information
discuss_preferences <- ifelse(T, "prompts/prompt.R", "prompts/prompt2.R") 

# C-D Utility Function Generator ------------------------------------------
# Randomly generate some Cobb-Douglas utility functions 
source("functions/util_gen.R")

# Endowment Generator -----------------------------------------------------
endowFn <- function() paste(round(abs(rnorm(mean = 500, sd = 250, n = 1))), "units of Good X and ", 
                            round(abs(rnorm(mean = 500, sd = 250, n = 1))), "units of Good Y")

# Make a vector of OpenAI instances ---------------------------------------
source(discuss_preferences)

create_openai_connections <- function(num_threads, sys_msg = msg) {
  connections <- vector("list", num_threads)
  for (i in seq_along(connections)) {
    goods_held <- endowFn()
    utilfn     <- utility_fn_generator(T)
    sys_msg_i  <- gsub("AAA", utilfn, sys_msg)
    sys_msg_i  <- gsub("BBB", goods_held, sys_msg_i)
    
    quantity_good_x <- as.numeric(gsub(" units of Good X and.*", "", 
                                       goods_held))
    quantity_good_y <- as.numeric(gsub(".* and\\s*(\\d+)\\s*units of Good Y", 
                                       "\\1", goods_held))
    
    sys_msg_i  <- gsub("CCC", round(eval(parse(
                        text = gsub("x", quantity_good_x,
                                  gsub("y", quantity_good_y, utilfn)))), 2), 
                        sys_msg_i)
    sys_msg_i  <- gsub("DDD", round(2*quantity_good_x, digits = 2), sys_msg_i)
    sys_msg_i  <- gsub("EEE", round(0.75*quantity_good_y, digits = 2), sys_msg_i)
    sys_msg_i  <- gsub("FFF", eval(parse(
                        text = gsub("x", 2*quantity_good_x,
                                    gsub("y", 0.75*quantity_good_y, utilfn)))
                        ), sys_msg_i)
    sys_msg_i  <- gsub("GGG", round(0.75*quantity_good_x, digits = 2), sys_msg_i)
    sys_msg_i  <- gsub("HHH", round(1.5*quantity_good_y, digits = 2), sys_msg_i)
    sys_msg_i  <- gsub("III", round(eval(parse(
                        text = gsub("x", 2*quantity_good_x,
                                    gsub("y", 0.75*quantity_good_y, utilfn)))), digits = 2), 
                        sys_msg_i)

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
source("functions/update_thread.R")

# Bargaining Pairs --------------------------------------------------------
# Function to facilitate conversation until consensus is reached
source("functions/exchange_messages.R")

# Function to manage multiple trading partners
source("functions/trading_pair_manager.R")

# Run the Experiment ------------------------------------------------------
# How many AI individuals (should be even)
total_num_nodes <- num_agents
even            <- function(x) x %% 2 == 0

# Main execution
trading_pair_manager(ifelse(even(total_num_nodes), 
                             total_num_nodes, 
                             total_num_nodes + 1), 
                      max_turns = max_turns)

# Append endowments to log
for(ai in unique(log_messages$sender)){
  endw <- log_messages$goods_held[min(as.numeric(rownames(
    log_messages[log_messages$sender==ai,])))]
  log_messages$endowment[log_messages$sender == ai] <- endw
}

log_messages$sender <- gsub(log_messages$sender, pattern = "thread_", 
                            replacement = "Agent ")

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
saveRDS(log_messages, paste0("log_messages_information_sharing_", 
                             timestamp, "_", ai_model, ".rds"))

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

log_messages$MU <- c(NA, round(diff(log_messages$utility), 3))
analytical_data <- log_messages[, colnames(log_messages) %in% c("sender", "turn",
                                                                "X", "Y", "utility",
                                                                "MU", "message")]
analytical_data$agent_total <- analytical_data$X + analytical_data$Y

# Calculate initial total goods in the economy
init_totals      <- analytical_data[analytical_data$turn == 0,]
init_total_goods <- sum(init_totals$agent_total)

# Extra validation logic
# analytical_data$valid_data <- NA
# turns <- unique(analytical_data$turn)
# 
# for (t in turns) {
#   turn_rows <- analytical_data[analytical_data$turn == t,]
#   if (nrow(turn_rows) == 2) {
#     agent1 <- turn_rows[1,]
#     agent2 <- turn_rows[2,]
#     # Check if Agent 2 accepted a trade
#     if (grepl("I accept", agent2$message, ignore.case = TRUE)) {
#       # Try to parse Agent 1's inventory from Agent 2's message
#       # Look for 'you have XXX units of Good X and YYY units of Good Y'
#       m <- regexec("you have (\\d+) units of Good X and (\\d+) units of Good Y", agent2$message)
#       parsed <- regmatches(agent2$message, m)
#       if (length(parsed[[1]]) == 3) {
#         agent1_X <- as.numeric(parsed[[1]][2])
#         agent1_Y <- as.numeric(parsed[[1]][3])
#         total_goods <- agent2$X + agent2$Y + agent1_X + agent1_Y
#         analytical_data$valid_data[analytical_data$turn == t] <- (total_goods == init_total_goods)
#       } else {
#         # Fallback: previous logic
#         prev2 <- analytical_data[analytical_data$sender == agent2$sender & analytical_data$turn == (t-1),]
#         if (nrow(prev2) == 1) {
#           dx <- agent2$X - prev2$X
#           dy <- agent2$Y - prev2$Y
#           valid <- (agent1$X + agent1$Y + agent2$X + agent2$Y + abs(dx) + abs(dy)) == init_total_goods
#           analytical_data$valid_data[analytical_data$turn == t] <- valid
#         } else {
#           analytical_data$valid_data[analytical_data$turn == t] <- FALSE
#         }
#       }
#     } else {
#       # Normal case: check if total matches initial
#       current_total <- sum(turn_rows$agent_total)
#       analytical_data$valid_data[analytical_data$turn == t] <- (current_total == init_total_goods)
#     }
#   } else {
#     # Only one agent's data for this turn, just check sum
#     current_total <- sum(turn_rows$agent_total)
#     analytical_data$valid_data[analytical_data$turn == t] <- (current_total == init_total_goods)
#   }
# }

# Utility Plot ------------------------------------------------------------
# Create a line plot of utility for each sender over turns
plot_data <- analytical_data[analytical_data$turn > 0, ]
plot_data <- plot_data[!grepl("ERROR", plot_data$message),]

utility_plot <-
  ggplot(plot_data, aes(x = turn, 
                        y = utility, 
                        color = sender, 
                        group = sender)) +
  # Thicker raw lines
  geom_line(linewidth = 1.2) +
  geom_point() +  
  # Add a smooth loess curve per sender
  #geom_smooth(method = "loess",
  #            se     = FALSE,
  #            size   = 1,    
  #            linetype = "dashed",
  #            alpha  = 0.6) +
  labs(title = "Marginal Utility over Negotiation Rounds",
       x     = "Negotiation Round #",
       y     = "Marginal Utility") +
  theme_minimal() +
  theme(legend.title = element_blank())
plot(utility_plot)

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
ggsave(filename = paste0("utility_plot_", timestamp, "_", ai_model, ".png"), 
       plot = utility_plot, 
       width = 10, height = 6, dpi = 300)


# Data Validation ---------------------------------------------------------
log_messages[log_messages$turn %in% c(0, max(log_messages$turn)), ] %>%
  select(sender, turn, X, Y) %>%
  print()

plot(utility_plot)

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

print("If the two sets of numbers above match then rationality held up well enough to have a valid result. To see how well of a result, consult the graph and check against a plain multi-objective optimization.")