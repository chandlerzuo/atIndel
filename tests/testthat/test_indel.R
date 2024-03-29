test_that("Error: mismatch between theta and the expected score difference.",
          {
            artifacts <- gen_test_artifacts()
            motif_len <- nrow(artifacts$pwm)
            for (insertion_len in c(1,
                                    as.integer(motif_len / 2),
                                    motif_len,
                                    motif_len + 1,
                                    motif_len * 2)) {
              score_percentile <- runif(n = 1, min = 0, max = 10)
              mat_d <-
                comp_indel_mat_d(artifacts$pwm, artifacts$prior, insertion_len)
              result_cpp <- test_importance_sample_indel(
                prior = artifacts$prior,
                transition = artifacts$trans_mat,
                pwm = artifacts$pwm,
                adj_pwm = artifacts$adj_pwm,
                mat_d = mat_d,
                insertion_len = insertion_len,
                score_percentile = score_percentile,
                loglik_type = 0,
                normalize_score_by_seq_len = FALSE
              )
              tol <- 1e-4
              expected_score_diff <-
                R_comp_expected_score_diff(
                  mat_d = mat_d,
                  insertion_len = insertion_len,
                  theta = result_cpp$theta,
                  adj_pwm = artifacts$adj_pwm,
                  pwm = artifacts$pwm,
                  prior = artifacts$prior
                )
              if (result_cpp$theta < 1 && result_cpp$theta > 0) {
                expect_equal(expected_score_diff, score_percentile, tolerance = tol)
              } else if (result_cpp$theta == 1) {
                expect_gte(score_percentile, expected_score_diff - tol)
              } else {
                expect_lte(score_percentile, expected_score_diff + tol)
              }
            }
          })


test_that("Error: normalization constant is not correct.", {
  artifacts <- gen_test_artifacts()
  motif_len <- nrow(artifacts$pwm)
  for (insertion_len in c(1,
                          as.integer(motif_len / 2),
                          motif_len,
                          motif_len + 1,
                          motif_len * 2)) {
    score_percentile <- runif(n = 1, min = 0, max = 10)
    mat_d <-
      comp_indel_mat_d(artifacts$pwm, artifacts$prior, insertion_len)
    result_cpp <- test_importance_sample_indel(
      prior = artifacts$prior,
      transition = artifacts$trans_mat,
      pwm = artifacts$pwm,
      adj_pwm = artifacts$adj_pwm,
      mat_d = mat_d,
      insertion_len = insertion_len,
      score_percentile = score_percentile,
      loglik_type = 0,
      normalize_score_by_seq_len = FALSE
    )
    cond_norm_const <-
      R_comp_cond_norm_const(mat_d = mat_d,
                             insertion_len = insertion_len,
                             theta = result_cpp$theta)
    expect_equal(cond_norm_const, result_cpp$cond_norm_const, tolerance = 0.01)
    expect_equal(result_cpp$norm_const, sum(cond_norm_const))
  }
})


test_that("Error: importance sample weights are not correct.", {
  artifacts <- gen_test_artifacts()
  motif_len <- nrow(artifacts$pwm)
  for (insertion_len in c(1,
                          as.integer(motif_len / 2),
                          motif_len,
                          motif_len + 1,
                          motif_len * 2)) {
    score_percentile <- runif(n = 1, min = 0, max = 10)
    mat_d <-
      comp_indel_mat_d(artifacts$pwm, artifacts$prior, insertion_len)
    result_cpp <- test_importance_sample_indel(
      prior = artifacts$prior,
      transition = artifacts$trans_mat,
      pwm = artifacts$pwm,
      adj_pwm = artifacts$adj_pwm,
      mat_d = mat_d,
      insertion_len = insertion_len,
      score_percentile = score_percentile,
      loglik_type = 0,
      normalize_score_by_seq_len = FALSE
    )
    result_r <- R_comp_importance_sample_weights(
      adj_pwm = artifacts$adj_pwm,
      mat_d = mat_d,
      theta = result_cpp$theta,
      prior = artifacts$prior,
      transition = artifacts$trans_mat,
      sample_seq = result_cpp$sample_sequence + 1
    )
    expect_equal(result_r$weight_joint,
                 result_cpp$weight_joint,
                 tolerance = 0.01)
    expect_equal(result_r$weight_base, result_cpp$weight_base, tolerance =
                   0.01)
  }
})

test_that("Error: max likelihood scores on the sequence pair are not correct.",
          {
            artifacts <- gen_test_artifacts()
            motif_len <- nrow(artifacts$pwm)
            for (insertion_len in c(1,
                                    as.integer(motif_len / 2),
                                    motif_len,
                                    motif_len + 1,
                                    motif_len * 2)) {
              score_percentile <- runif(n = 1, min = 0, max = 10)
              mat_d <-
                comp_indel_mat_d(artifacts$pwm, artifacts$prior, insertion_len)
              result_cpp <- test_importance_sample_indel(
                prior = artifacts$prior,
                transition = artifacts$trans_mat,
                pwm = artifacts$pwm,
                adj_pwm = artifacts$adj_pwm,
                mat_d = mat_d,
                insertion_len = insertion_len,
                score_percentile = score_percentile,
                loglik_type = 0,
                normalize_score_by_seq_len = FALSE
              )
              expect_equal(
                R_motif_score_max(
                  sample_seq = result_cpp$sample_sequence + 1,
                  pwm = artifacts$pwm
                ),
                result_cpp$long_seq_score,
                tolerance = 1e-4
              )
              expect_equal(
                R_motif_score_max(
                  sample_seq = result_cpp$sample_sequence[-(motif_len:(motif_len + insertion_len -
                                                                         1))] + 1,
                  pwm = artifacts$pwm
                ),
                result_cpp$short_seq_score,
                tolerance = 1e-4
              )
            }
          })


test_that("Error: distribution of the motif scores is not correct.",
          {
            artifacts <- gen_test_artifacts()
            motif_len <- nrow(artifacts$pwm)
            sample_size <- 100
            for (insertion_len in c(1,
                                    as.integer(motif_len / 2),
                                    motif_len,
                                    motif_len + 1,
                                    motif_len * 2)) {
              score_percentile <- runif(n = 1, min = 0, max = 10)
              mat_d <-
                comp_indel_mat_d(artifacts$pwm, artifacts$prior, insertion_len)
              score_pairs <-
                sapply(seq_len(sample_size), function(x) {
                  result_cpp <- test_importance_sample_indel(
                    prior = artifacts$prior,
                    transition = artifacts$trans_mat,
                    pwm = artifacts$pwm,
                    adj_pwm = artifacts$adj_pwm,
                    mat_d = mat_d,
                    insertion_len = insertion_len,
                    score_percentile = score_percentile,
                    loglik_type = 0,
                    normalize_score_by_seq_len = FALSE
                  )
                  R_sample_seq <- R_gen_importance_sample(
                    prior = artifacts$prior,
                    trans_mat = artifacts$trans_mat,
                    adj_pwm = artifacts$adj_pwm,
                    mat_d = mat_d,
                    insertion_len = insertion_len,
                    cond_norm_const = result_cpp$cond_norm_const,
                    theta = result_cpp$theta
                  )
                  R_long_seq_score <-
                    R_motif_score_max(sample_seq = R_sample_seq, pwm = artifacts$pwm)
                  motif_len <- nrow(artifacts$pwm)
                  R_short_seq_score <-
                    R_motif_score_max(sample_seq = R_sample_seq[-(motif_len:(motif_len + insertion_len - 1))], pwm = artifacts$pwm)
                  return(
                    c(
                      result_cpp$long_seq_score,
                      result_cpp$short_seq_score,
                      R_long_seq_score,
                      R_short_seq_score
                    )
                  )
                })
              suppressWarnings({
                # NOTE: ks.test warns about ties
                expect_gte(ks.test(score_pairs[1,], score_pairs[3, ])$p.value, 0.01)
                expect_gte(ks.test(score_pairs[2,], score_pairs[4, ])$p.value, 0.01)
              })
            }
          })


test_that("Error: max log lik score is not consistent with the matching position",
          {
            artifacts <- gen_test_artifacts()
            motif_len <- nrow(artifacts$pwm)
            n_indels <- 10
            indel_info <- list()
            for (i in seq_len(n_indels)) {
              offset <- sample(0:3, size = 1)
              insertion_len <- sample(seq_len(10), size = 1)
              indel_info[[i]] <- list(
                inserted_sequence = sample(
                  seq_len(4),
                  size = motif_len * 2 - 2 + insertion_len +
                    offset * 2,
                  replace = TRUE
                ),
                insertion_len = insertion_len
              )
            }
            motif_scores <- .Call("comp_indel_motif_scores",
                                  list(artifacts$pwm),
                                  indel_info,
                                  0,
                                  package = "atIndel")
            for (i in seq_len(n_indels)) {
              long_seq <- indel_info[[i]]$inserted_sequence
              insertion_len <- indel_info[[i]]$insertion_len
              short_seq_len <- length(long_seq) - insertion_len
              short_seq <-
                c(long_seq[1:(short_seq_len / 2)], long_seq[(short_seq_len / 2 + insertion_len + 1):length(long_seq)])
              offset <- length(short_seq) / 2 - motif_len + 1

              long_seq_score <- R_motif_score_subseq(
                long_seq,
                artifacts$pwm,
                abs(motif_scores$match_pos_long[i]),
                motif_scores$match_pos_long[i] < 0
              )
              short_seq_score <- R_motif_score_subseq(
                short_seq,
                artifacts$pwm,
                abs(motif_scores$match_pos_short[i]),
                motif_scores$match_pos_short[i] < 0
              )
              expect_equal(long_seq_score, motif_scores$log_lik_long[i], 1e-3)
              expect_equal(short_seq_score, motif_scores$log_lik_short[i], 1e-3)

              long_seq_score <-
                R_motif_score_max(long_seq[(offset + 1):(length(long_seq) -
                                                           offset)],
                                  artifacts$pwm)
              short_seq_score <-
                R_motif_score_max(short_seq[(offset + 1):(length(short_seq) -
                                                            offset)],
                                  artifacts$pwm)
              expect_equal(long_seq_score, motif_scores$log_lik_long[i], 1e-3)
              expect_equal(short_seq_score, motif_scores$log_lik_short[i], 1e-3)
            }
          })
