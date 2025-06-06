# File: util_gen.R
utility_fn_generator <- function(text = F) {
  # (Semi-) random parameters constrained to valid range for C-D
  paramFn <- function() max(min(abs(rnorm(1, mean = 0.1, sd = 0.1)), 1), 0)
  a_value <- paramFn()
  b_value <- paramFn()
  
  expr <- expression((log(x) * a) + (log(y) * b))
  
  expr_substituted <- eval(substitute(substitute(e, list(a = a_value, b = b_value)), list(e = expr)))
  
  # Utility function
  utility <- function(x, y) {
    utils <- function(x, y) eval(expr_substituted)
    return(utils(x, y))
  }
  
  if (text) utility <- gsub("b", b_value, gsub("a", a_value, "(x^a) * (y^b)"))
  return(utility)
}