#' Generate a random sequence following Markov Chain
gen_mc_sequence <- function(prior, transition, sequence_len) {
  dict_size <- length(prior)
  if (dict_size != ncol(transition) ||
      dict_size != nrow(transition)) {
    stop(
      "Incorrect dimension for Markov params, get ",
      length(prior),
      ", (",
      nrow(transition),
      ", ",
      ncol(transition),
      ")."
    )
  }
  sample_seq <- rep(0, sequence_len)
  sample_seq[1] <-
    sample(
      seq_len(dict_size),
      size = 1,
      replace = TRUE,
      prob = prior
    )
  if (sequence_len > 1) {
    for (i in 2:sequence_len) {
      sample_seq[i] <-
        sample(
          seq_len(dict_size),
          size = 1,
          replace = TRUE,
          prob = transition[sample_seq[i - 1], ]
        )
    }
  }
  return(sample_seq)
}


#' Find the log-lik score for the best matching subsequence to an PWM.
R_motif_score_max <- function(sample_seq, pwm) {
  maxlogp <- -Inf
  motif_len <- nrow(pwm)
  for (start_pos in seq(length(sample_seq) - motif_len + 1)) {
    maxlogp <- max(c(
      maxlogp,
      R_motif_score_subseq(sample_seq, pwm, start_pos, FALSE),
      R_motif_score_subseq(sample_seq, pwm, start_pos, TRUE)
    ))
  }
  return(maxlogp)
}


#' Find the log-lik score for the best matching subsequence to an PWM.
R_motif_score_mean <- function(sample_seq, pwm) {
  motif_len <- nrow(pwm)
  return(max(c(mean(
    vapply(seq(length(sample_seq) - motif_len + 1),
           function(start_pos)
             R_motif_score_subseq(sample_seq, pwm, start_pos, FALSE), 0)
  ),
  mean(
    vapply(seq(length(sample_seq) - motif_len + 1),
           function(start_pos)
             R_motif_score_subseq(sample_seq, pwm, start_pos, TRUE), 0)
  ))))
}

#' Find the log-lik score for a subsequence to an PWM.
R_motif_score_subseq <-
  function(sample_seq, pwm, start_pos, reverse) {
    motif_len <- nrow(pwm)
    if (reverse) {
      ret <-
        sum(log(pwm[cbind(seq(motif_len), (ncol(pwm) + 1 - rev(sample_seq))[start_pos:(start_pos + motif_len - 1)])]))
      return(ret)
    }
    ret <-
      sum(log(pwm[cbind(seq(motif_len), sample_seq[start_pos:(start_pos + motif_len - 1)])]))
    return(ret)
  }


#' Generate artifacts for unit tests.
gen_test_artifacts <- function() {
  data(example)
  # NOTE: don't choose a motif with 0/1 probabilities here. Certain tests may
  # fail due to such degenerate PWMs.
  test_pwm <- motif_lib$`Ddit3::Cebpa`
  adj_pwm <- (test_pwm + 0.25) / apply(test_pwm + 0.25, 1, sum)
  return(list(
    prior = prior,
    trans_mat = trans_mat,
    pwm = test_pwm,
    adj_pwm = adj_pwm
  ))
}
