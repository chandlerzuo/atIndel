#' @name pvalue_single_thread_helper
#' @title Compute the p-values for score change for a single motif and
#' a set of indels with the same insertion length.
#' @param pwm A numeric matrix for the position weight matrix of the motif.
#' @param motif_name A character for the motif name.
#' @param indel_info A list for information related to indels. See the
#' argument for \code{\link{indel_p_values}} for more details.
#' @param motif_scores A numeric matrix including two column. The first column
#' is the scores for the longer sequences. The 2nd column is the scores for the
#' shorter sequences. Each row corresponding to one indel.
#' @param prior A numeric vector for the prior of the Markov Chain background
#' model.
#' @param trans_mat A numeric matrix for the transition matrix of the Markov
#' Chain background model.
#' @param sample_size An integer for the Monte-Carlo sample size.
#' @param normalize_score_by_seq_len Boolean for whether scores are normalized
#' by sequence lengths.
#' @param pval_method 0: rank test only. 1: binding score difference test only. 2: both.
#' @importFrom plyr ldply
#' @return A data frame.
pvalue_single_thread_helper <-
  function(pwm,
           motif_name,
           indel_info,
           motif_scores,
           prior,
           trans_mat,
           sample_size,
           normalize_score_by_seq_len,
           pval_method) {
    if (length(unique(sapply(indel_info, "[[", "insertion_len"))) != 1) {
      stop("All indels must have the same insertion length.")
    }

    message(
      "Calculate p-values for motif ",
      motif_name,
      " and indels ",
      paste(names(indel_info), collapse = ", "),
      "."
    )
    results2 <- list()
    result_id <- 1

    for (indel_id in seq_along(indel_info)) {
      # Step 2. Compute single allele p-values
      this_indel_info <- indel_info[[indel_id]]

      scores <- motif_scores[indel_id, , drop = FALSE]

      p_value_affinity <- rep(0, 2)
      for (j in seq(2)) {
        if (j == 1) {
          # for long sequence
          sample_seq_len <-
            2 * nrow(pwm) - 2 + this_indel_info$insertion_len
          reference_score <- motif_scores[indel_id, 1]
        } else  if (j == 2) {
          # j=2 for short sequence
          sample_seq_len <- 2 * nrow(pwm) - 2
          reference_score <- motif_scores[indel_id, 2]
        }
        # Compute theta parameter in importance sampling distribution
        theta <- .Call(
          "test_find_theta",
          pwm,
          prior,
          trans_mat,
          # Importance sample scores will have
          # average value of reference score.
          reference_score,
          sample_seq_len,
          package = "atIndel"
        )
        p_value_affinity[j] <- pval_with_less_var(
          .Call(
            "compute_p_values",
            # PWM
            pwm,
            # MC stationary distribution
            prior,
            # transition matrix
            trans_mat,
            scores[, j],
            # theta parameter in importance sampling
            theta,
            sample_size,
            # The sequence length
            sample_seq_len,
            # Use 1 for mean log lik scores
            loglik_type = 0,
            package = "atIndel"
          )[, seq(4)] # the first 4 columns are p-values
          # The last 4 columns are conditional p-values and are not used.
        )[, 1]
      }

      mat_d <-
        comp_indel_mat_d(pwm, prior, this_indel_info$insertion_len)
      # reference_score is used to compute the theta parameter in importance
      # sampling.
      if (normalize_score_by_seq_len) {
        # normalize the scores
        score_diff <- c(scores[, 1]  / (2 * nrow(pwm) - 2 + this_indel_info$insertion_len)
          - scores[, 2] / (2 * nrow(pwm) - 2))
        reference_score <-
          c(motif_scores[indel_id, 1] / (2 * nrow(pwm) - 2 + this_indel_info$insertion_len)
          - motif_scores[indel_id, 2] / (2 * nrow(pwm) - 2))
      } else {
        score_diff <- c(scores[, 1] - scores[, 2])
        reference_score <-
          motif_scores[indel_id, 1] - motif_scores[indel_id, 2]
      }
      p_value_change <-
        .Call(
          "p_value_change_indel",
          # Markov Chain transition matrix
          trans_mat,
          # Markov Chain stationary distribution
          prior,
          # The D matrix used to induce binding affinity change
          mat_d,
          # Insertion length
          this_indel_info$insertion_len,
          # PWM
          pwm,
          # Adjusted PWM
          (pwm + 0.25) / 2,
          score_diff,
          c(log(p_value_affinity[1]) - log(p_value_affinity[2])),
          # This is used to compute the theta parameter in importance
          # sampling.
          reference_score,
          sample_size,
          0, # loglik_type
          normalize_score_by_seq_len,
          pval_method,
          package = "atIndel"
        )
      if (pval_method == 0) {
        p_value_change = list(
          rank = pval_with_less_var(p_value_change$rank)[, 1],
          score = rep(NA, length(p_value_change$rank))
        )
      } else if (pval_method == 1) {
        p_value_change = list(
          score = pval_with_less_var(p_value_change$score)[, 1],
          rank = rep(NA, length(p_value_change$score))
        )
      } else {
        p_value_change = list(
          rank = pval_with_less_var(p_value_change$rank)[, 1],
          score = pval_with_less_var(p_value_change$score)[, 1]
        )
      }
      results2[[result_id]] <- list(
        motif_scores = scores,
        p_value_change = p_value_change,
        p_value_affinity1 = p_value_affinity[1],
        p_value_affinity2 = p_value_affinity[2]
      )
      result_id <- result_id + 1
    }
    r <- plyr::ldply (results2, data.frame)
    message("converted to dataframe")
    r <-
      data.frame(id <-
                   rep(names(indel_info)),
                 motif = motif_name, r)
    colnames(r)[1] <- "id"
    message(
      "Finished p-value calculation for motif ",
      motif_name,
      " and indels ",
      paste(names(indel_info), collapse = ", "),
      "."
    )
    return(r)
  }


make_insertion_tbl <- function(a, long_insertion) {
  a <- merge(a, long_insertion, by = "id", all.x = TRUE)
  a$ref.score <-
    ifelse(a$insertion, a$motif_scores.2, a$motif_scores.1)
  a$mutation.score <-
    ifelse(a$insertion, a$motif_scores.1, a$motif_scores.2)
  a$ref.pval <-
    ifelse(a$insertion, a$p_value_affinity2, a$p_value_affinity1)
  a$mutation.pval <-
    ifelse(a$insertion, a$p_value_affinity1, a$p_value_affinity2)
  a2 <- a[, c(1, 2, 9, 10, 12, 13, 14, 15, 5, 6, 11)]
  a2
}

make_motifscore_insertion_tbl <- function(a, long_insertion) {
  a <- merge(a, long_insertion, by = "id", all.x = TRUE)
  a$ref.score <-
    ifelse(a$insertion, a$log_lik_short, a$log_lik_long)
  a$mutation.score <-
    ifelse(a$insertion, a$log_lik_long, a$log_lik_short)
  a2 <- a[, c(1, 2, 6, 7, 9, 10, 5, 8)]
  a2
}


#' @name indel_motif_scores
#' @title Compute the motif scores given a motif library and a list of indels.
#' @description Compute the motif scores given a motif library and a list of
# indels.
#' @param motif_lib A list of the position weight matrices for the motifs.
#' @param indel_info A list object. Each element corresponds to an indel.
#' See \link{indel_info} for details and an example.
#' @param num_cores An integer for the number of parallel processes used for
#' parallel computation.
#' @details TODO.
#' @return A list object of position weight matrices.
#' @author Qinyi Zhou \email{qinyi.zhou@utdallas.edu},
#' Chandler Zuo \email{chandler.c.zuo@@gmail.com},
#' Sunyoung Shin \email{sunyoung.shin@@utdallas.edu}
#' @examples
#' data(example)
#' indel_motif_scores(motif_lib, indel_info, num_cores=1)
#' @useDynLib atIndel
#' @import Rcpp
#' @importFrom BiocParallel bpmapply MulticoreParam SnowParam
#' @export
indel_motif_scores <-
  function(motif_lib, indel_info, num_cores = 1) {
    motifs <- names(motif_lib)
    ids <- names(indel_info)
    num_motifs <- length(motif_lib)
    sequence_len <- length(indel_info)

    if (length(unique(motifs)) != length(motifs)) {
      stop("Motif names in 'motif_lib' are not unique.")
    }
    if (length(unique(ids)) != length(ids)) {
      stop("Indel names in 'indel_info' are not unique.")
    }

    num_cores <- min(num_cores, num_motifs)
    k <- as.integer(num_motifs / num_cores)
    insertion <- unlist(lapply(indel_info, `[[`, 3))
    ref <- unlist(lapply(indel_info, `[[`, 4))
    alt <- unlist(lapply(indel_info, `[[`, 5))
    long_insertion <-
      data.frame(
        id = ids,
        ref = ref,
        alt = alt,
        insertion = insertion
      )
    if (num_cores > 1) {
      # TODO: refactor to remove code duplication.
      # 1. Write a function motif_single_thread_helper that does calculation
      # for a single motif; 2. use this function for all of Windows / Mac
      # / non-parallel settings. Use lines after line 515 and
      # pvalue_single_thread_helper as an example.
      if (Sys.info()[["sysname"]] == "Windows") {
        snow <- BiocParallel::SnowParam(workers = num_cores, type = "SOCK")
        motif_score_par <- function(i,
                                    k,
                                    num_cores,
                                    num_motifs,
                                    sequence_len,
                                    motif_lib,
                                    indel_info) {
          ret <- list()
          # TODO: In parallel calculation, we don't need to manually partition
          # motifs in to num_cores groups as here. We only need to sepcify
          # # of threads (num_cores). Each of them will pick one motif,
          # calculate the scores. Once the calculation is done, the thread will
          # pick up another motif that has not been calculated and continue the
          # calculation. All threads will finish at the same time. Use lines
          # after line 515 as an example.
          if (num_motifs >= ((k - 1) * num_cores + i)) {
            nm <- c(0:(k - 1)) * num_cores + i
          } else{
            nm <- c(0:(k - 2)) * num_cores + i
          }
          motif_scores <- .Call(
            "comp_indel_motif_scores",
            motif_lib[nm],
            indel_info,
            # select the log-lik type here
            0, #loglik_type
            package = "atIndel"
          )
          ret$num <- nm
          ret$motif_scores <- motif_scores
          ret
        }

        motif_score_par_list <-
          BiocParallel::bpmapply(
            function(x)
              motif_score_par(
                i = x,
                k = k,
                num_cores = num_cores,
                num_motifs = num_motifs,
                sequence_len = sequence_len,
                motif_lib = motif_lib,
                indel_info = indel_info
              ),
            seq(num_cores),
            BPPARAM = snow,
            SIMPLIFY = FALSE
          )
        nm <- unlist(lapply(motif_score_par_list, `[[`, 1))
        id <- rep(ids, num_motifs)
        ins <- rep(insertion, num_motifs)
        motif <- rep(motifs[nm], each = sequence_len)
        ms <- lapply(lapply(motif_score_par_list, `[[`, 2), `[[`, 1)
        ml <- lapply(lapply(motif_score_par_list, `[[`, 2), `[[`, 2)
        short <-
          lapply(lapply(motif_score_par_list, `[[`, 2), `[[`, 4)
        long <-
          lapply(lapply(motif_score_par_list, `[[`, 2), `[[`, 5)
        ratio <-
          lapply(lapply(motif_score_par_list, `[[`, 2), `[[`, 3)
        match_pos_short <- ms[[1]]
        match_pos_long <- ml[[1]]
        log_lik_short <- short[[1]]
        log_lik_long <- long[[1]]
        log_lik_ratio <- ratio[[1]]
        for (i in (2:num_cores)) {
          match_pos_short <- cbind(match_pos_short, ms[[i]])
          match_pos_long <- cbind(match_pos_long, ml[[i]])
          log_lik_short <- cbind(log_lik_short, short[[i]])
          log_lik_long <- cbind(log_lik_long, long[[i]])
          log_lik_ratio <- cbind(log_lik_ratio, ratio[[i]])
        }
        motif_scores <- list()
        motif_scores$match_pos_short <- match_pos_short
        motif_scores$match_pos_long <- match_pos_long
        motif_scores$log_lik_ratio <- log_lik_ratio
        motif_scores$log_lik_short <- log_lik_short
        motif_scores$log_lik_long <- log_lik_long
        result <- list()
        x <-
          data.frame(
            id,
            motif,
            log_lik_short = as.vector(log_lik_short),
            log_lik_long = as.vector(log_lik_long),
            log_lik_ratio = as.vector(log_lik_ratio)
          )
        result$table <-
          make_motifscore_insertion_tbl(x, long_insertion)
        result$list <- motif_scores
        result$list$motif <- motifs
        result$list$k <- nm
        result$list$insertion <- insertion
        result$list$ref <- ref
        result$list$alt <- alt
        result
      } else{
        mac_motif_score_par <-
          function(i,
                   k,
                   num_cores,
                   num_motifs,
                   sequence_len,
                   motif_lib,
                   indel_info) {
            ret <- list()
            if (num_motifs >= k * num_cores + i) {
              nm <- c(0:k) * num_cores + i
            } else{
              nm <- c(0:(k - 1)) * num_cores + i
            }
            motif_scores <- .Call(
              "comp_indel_motif_scores",
              motif_lib[nm],
              indel_info,
              # select the log-lik type here
              0,
              package = "atIndel"
            )
            ret$num <- nm
            ret$motif_scores <- motif_scores
            ret
          }
        motif_score_par_list <-
          BiocParallel::bpmapply(
            function(x)
              mac_motif_score_par(
                i = x,
                k = k,
                num_cores = num_cores,
                num_motifs = num_motifs,
                sequence_len = sequence_len,
                motif_lib = motif_lib,
                indel_info = indel_info
              ),
            seq(num_cores),
            BPPARAM = MulticoreParam(workers = num_cores),
            SIMPLIFY = FALSE
          )
        nm <- unlist(lapply(motif_score_par_list, `[[`, 1))
        id <- rep(ids, num_motifs)
        motif <- rep(motifs[nm], each = sequence_len)
        ms <- lapply(lapply(motif_score_par_list, `[[`, 2), `[[`, 1)
        ml <- lapply(lapply(motif_score_par_list, `[[`, 2), `[[`, 2)
        short <-
          lapply(lapply(motif_score_par_list, `[[`, 2), `[[`, 4)
        long <-
          lapply(lapply(motif_score_par_list, `[[`, 2), `[[`, 5)
        ratio <-
          lapply(lapply(motif_score_par_list, `[[`, 2), `[[`, 3)
        match_pos_short <- ms[[1]]
        match_pos_long <- ml[[1]]
        log_lik_short <- short[[1]]
        log_lik_long <- long[[1]]
        log_lik_ratio <- ratio[[1]]
        for (i in (2:num_cores)) {
          match_pos_short <- cbind(match_pos_short, ms[[i]])
          match_pos_long <- cbind(match_pos_long, ml[[i]])
          log_lik_short <- cbind(log_lik_short, short[[i]])
          log_lik_long <- cbind(log_lik_long, long[[i]])
          log_lik_ratio <- cbind(log_lik_ratio, ratio[[i]])
        }
        motif_scores <- list()
        motif_scores$match_pos_short <- match_pos_short
        motif_scores$match_pos_long <- match_pos_long
        motif_scores$log_lik_ratio <- log_lik_ratio
        motif_scores$log_lik_short <- log_lik_short
        motif_scores$log_lik_long <- log_lik_long
        result <- list()
        x <-
          data.frame(
            id,
            motif,
            log_lik_short = as.vector(log_lik_short),
            log_lik_long = as.vector(log_lik_long),
            log_lik_ratio = as.vector(log_lik_ratio)
          )
        result$table <-
          make_motifscore_insertion_tbl(x, long_insertion)
        result$list <- motif_scores
        result$list$motif <- motifs
        result$list$k <- nm
        result$list$insertion <- insertion
        result$list$ref <- ref
        result$list$alt <- alt
      }
    } else{
      motif_scores <- .Call(
        "comp_indel_motif_scores",
        motif_lib,
        indel_info,
        # select the log-lik type here
        0,
        package = "atIndel"
      )

      id <- rep(ids, num_motifs)
      motif <- rep(motifs, each = sequence_len)
      log_lik_short <- as.vector(motif_scores$log_lik_short)
      log_lik_long <- as.vector(motif_scores$log_lik_long)
      log_lik_ratio <- as.vector(motif_scores$log_lik_ratio)

      result <- list()
      x <-
        data.frame(
          id,
          motif,
          log_lik_short = as.vector(log_lik_short),
          log_lik_long = as.vector(log_lik_long),
          log_lik_ratio = as.vector(log_lik_ratio)
        )
      result$table <-
        make_motifscore_insertion_tbl(x, long_insertion)
      result$list <- motif_scores
      result$list$motif <- motifs
      result$list$k <- seq(num_motifs)
      result$list$insertion <- insertion
      result$list$ref <- ref
      result$list$alt <- alt
    }
    return(result)
  }


#' @name indel_p_values
#' @title Compute the motif scores given a motif library and a list of indels.
#' @description Compute the motif scores given a motif library and a list of
# indels.
#' @param motif_lib A list of the position weight matrices for the motifs.
#' @param indel_info A list object. Each element corresponds to an indel.
#' See \link{indel_info} for details and an example.
#' @param motif_scores A data frame in the same format as the output of
#' \code{\link{indel_motif_scores}}.
#' @param prior A numeric vector for the prior distribution parameters of
# the Markov Chain model for background sequences.
#' @param trans_mat A numeric matrix for the transition matrix parameters
#  of the Markov Chain model for background sequences.
#' @param sample_size An integer for the importance sampling sample size.
#' @param normalize_score_by_seq_len Boolean for whether the scores are
#' normalized by the sequence lengths. Default: TRUE.
#' @param pval_method 0: rank test only. 1: binding score diff test only.
#' 2: both. Default: 2.
#' @param num_cores An integer for the number of parallel processes.
#' @details TODO.
#' @return A list object of position weight matrices.
#' @author Qinyi Zhou \email{qinyi.zhou@utdallas.edu},
#' Chandler Zuo \email{chandler.c.zuo@@gmail.com},
#' Sunyoung Shin \email{sunyoung.shin@@utdallas.edu}
#' @examples
#' data(example)
#' motif_scores <- indel_motif_scores(motif_lib, indel_info)$list
#' indel_p_values(
#'   motif_lib=motif_lib,
#'   indel_info=indel_info,
#'   motif_scores=motif_scores,
#'   prior=prior,
#'   trans_mat=trans_mat,
#'   sample_size=100,
#'   normalize_score_by_seq_len=FALSE,
#'   pval_method=2,
#'   num_cores=1
#' )
#' @useDynLib atIndel
#' @import Rcpp
#' @importFrom BiocParallel bpmapply MulticoreParam SnowParam
#' @export
indel_p_values <-
  function(motif_lib,
           indel_info,
           motif_scores,
           prior,
           trans_mat,
           sample_size,
           normalize_score_by_seq_len = TRUE,
           pval_method = 2,
           num_cores = 1) {
    validate_motif_scores(motif_scores, names(motif_lib), names(indel_info))

    indel_info_sorted <- rlist::list.sort(indel_info, insertion_len)
    m_list <- unlist(lapply(indel_info_sorted, `[[`, 2))
    insertion_lens <- unique(m_list)
    ids <- names(indel_info_sorted)
    num_motifs <- length(motif_lib)
    num_cores <- min(num_cores, num_motifs)
    motif_scores <- motif_scores
    prior <- prior
    insertion <- unlist(lapply(indel_info_sorted, `[[`, 3))
    ref <- unlist(lapply(indel_info_sorted, `[[`, 4))
    alt <- unlist(lapply(indel_info_sorted, `[[`, 5))
    long_insertion <-
      data.frame(
        id = ids,
        ref = ref,
        alt = alt,
        insertion = insertion
      )

    param_list <- list()
    for (insertion_len in insertion_lens) {
      for (motif_name in names(motif_lib)) {
        motif_id <- which(motif_scores$motif == motif_name)
        x <- which(lapply(indel_info, `[[`, 2) == insertion_len)
        indel_info_selected <- indel_info[x]
        param_list <- rlist::list.append(
          param_list,
          list(
            indel_info = indel_info_selected,
            motif_scores = matrix(
              c(
                motif_scores$log_lik_long[x, motif_id],
                motif_scores$log_lik_short[x, motif_id]
              ),
              ncol = 2
            ),
            motif_name = motif_name,
            pwm = motif_lib[[motif_name]]
          )
        )
      }
    }

    if (num_cores > 1) {
      if (Sys.info()[["sysname"]] == "Windows") {
        bp_param <-
          BiocParallel::SnowParam(
            workers = num_cores,
            type = "SOCK",
            progressbar = TRUE,
            tasks = length(param_list)
          )
        # NOTE: for some reason BiocParallel complains not
        # finding this object without doing so.
        trans_mat <- trans_mat
      } else {
        bp_param <-
          BiocParallel::MulticoreParam(
            workers = num_cores,
            progressbar = TRUE,
            tasks = length(param_list)
          )
      }
      results <-
        BiocParallel::bpmapply(
          function(param)
            pvalue_single_thread_helper(
              motif_name = param$motif_name,
              pwm = param$pwm,
              indel_info = param$indel_info,
              motif_scores = param$motif_scores,
              prior = prior,
              trans_mat = trans_mat,
              sample_size = sample_size,
              normalize_score_by_seq_len = normalize_score_by_seq_len,
              pval_method = pval_method
            ),
          param_list,
          BPPARAM = bp_param,
          SIMPLIFY = FALSE
        )
    } else
    {
      results <-
        mapply(
          function(param)
            pvalue_single_thread_helper(
              motif_name = param$motif_name,
              pwm = param$pwm,
              indel_info = param$indel_info,
              motif_scores = param$motif_scores,
              prior = prior,
              trans_mat = trans_mat,
              sample_size = sample_size,
              normalize_score_by_seq_len = normalize_score_by_seq_len,
              pval_method = pval_method
            ),
          param_list,
          SIMPLIFY = FALSE
        )
    }
    merged_result <- do.call(rbind.data.frame,  results)
    merged_result <- merged_result[order(merged_result$id),]
    rownames(merged_result) <- seq_len(nrow(merged_result))
    merged_result <-
      make_insertion_tbl(merged_result, long_insertion)
    return(merged_result)
  }
