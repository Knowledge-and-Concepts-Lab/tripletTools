import pandas as pd
import numpy as np
import random
import torch
from salmon.triplets.offline import OfflineEmbedding
import os


def _fit_offline(X_train, X_test, n, d, max_epochs, tolerance, tol_window, print_every,
                  device, noise_model="CKL", embedding=None, random_state=None,
                  module_kwargs=None, stage_label=None):
    """
    Run one early-stopped OfflineEmbedding fit. Shared by the plain Euclidean
    path and each stage of the spherical warm-start recipe in
    ``train_embedding_model``.

    Returns the same 5-tuple as ``train_embedding_model``.
    """
    module_kwargs = module_kwargs or {}

    model = OfflineEmbedding(n=n, d=d, max_epochs=max_epochs, verbose=100, device=device,
                              noise_model=noise_model, random_state=random_state, **module_kwargs)
    model.initialize(X_train, embedding=embedding)

    current_lowest_loss = 1
    current_best_embedding = model.embedding_
    counter_since_update = 0
    epoch_history = []

    # Score every score_every epochs rather than every epoch.
    # Scoring the full dataset every epoch is the dominant cost for large
    # datasets: with 50k triplets and 50k epochs it means billions of
    # evaluations before any gradient work counts. Checking every
    # tol_window//100 epochs gives ~100 monitoring points per tolerance
    # window, which is more than enough for reliable early stopping.
    score_every = max(1, tol_window // 100)

    header = f"{'Epoch':>8}  {'Train Loss':>10}  {'Test Loss':>10}  {'Train Acc':>10}  {'Test Acc':>10}"
    if stage_label:
        print(stage_label)
    print(header)
    print("-" * len(header))

    train_acc = train_loss = test_acc = test_loss = float("nan")

    for epoch in range(max_epochs):
        model.partial_fit(X_train)

        if epoch % score_every == 0 or epoch == max_epochs - 1:
            train_acc, train_loss = model._score(X_train)
            test_acc,  test_loss  = model._score(X_test)

            epoch_history.append({
                "epoch":      epoch,
                "train_loss": train_loss,
                "test_loss":  test_loss,
                "train_acc":  train_acc,
                "test_acc":   test_acc,
            })

            if epoch % print_every == 0:
                print(f"{epoch:>8}  {train_loss:>10.4f}  {test_loss:>10.4f}  {train_acc:>10.4f}  {test_acc:>10.4f}")

            if test_loss < current_lowest_loss:
                current_lowest_loss = test_loss
                current_best_embedding = model.embedding_
                counter_since_update = 0
            else:
                counter_since_update += score_every

            if counter_since_update > tol_window:
                print(f"{epoch:>8}  {train_loss:>10.4f}  {test_loss:>10.4f}  {train_acc:>10.4f}  {test_acc:>10.4f}  [early stop]")
                break
    else:
        print(f"{epoch:>8}  {train_loss:>10.4f}  {test_loss:>10.4f}  {train_acc:>10.4f}  {test_acc:>10.4f}  [max epochs]")

    # Return history as a plain dict of lists rather than a pandas DataFrame.
    # Reticulate's conversion of pandas DataFrames to R data frames is
    # inconsistent across execution contexts (interactive vs multisession
    # workers), causing hard-to-reproduce errors on the R side. A plain Python
    # dict is always converted to a named R list, which as.data.frame() handles
    # reliably.
    history = pd.DataFrame(epoch_history).to_dict("list")
    return current_best_embedding, current_lowest_loss, epoch, counter_since_update, history


def train_embedding_model(X_train, X_test, d=5, max_epochs=50_000, tolerance=1e-4, tol_window=10_000,
                           print_every=100, device=None, random_state=None,
                           geometry="euclidean", radius=1.0, warm_start=None):
    """
    Train embedding model with early stopping based on test loss.

    Parameters:
    X_train: numpy array of training triplets (head, winner, loser)
    X_test: numpy array of test triplets (head, winner, loser)
    d: embedding dimensions
    max_epochs: maximum training epochs
    tolerance: loss improvement threshold for early stopping
    tol_window: epochs without meaningful improvement before stopping
    print_every: print progress every this many epochs (default 100)
    geometry: "euclidean" (default) or "sphere". When "sphere", points are
        constrained to the surface of a d-dimensional sphere of radius
        ``radius`` (d=2 is a circle) rather than living freely in R^d.
        Distances between constrained points are used directly in the noise
        model, which is mathematically equivalent to great-circle distance
        for points on a common sphere (see salmon's ``_spherical.py`` for
        why) but numerically better behaved.

        Fitting a spherical embedding from a random start reliably gets
        stuck near chance accuracy: the sphere's tangent space gives each
        point only d-1 degrees of freedom to move along, too few for
        gradient descent to escape a bad ordering. So when geometry="sphere"
        and no ``warm_start`` is given, this function first fits a free
        Euclidean embedding (same d, same early-stopping schedule), projects
        it onto the sphere, and uses that as the starting point for the
        constrained fit. This roughly doubles training cost relative to
        geometry="euclidean", but is necessary for the constrained fit to
        find good solutions.
    radius: radius of the sphere when geometry="sphere". Ignored otherwise.
    warm_start: optional (n, d) numpy array of existing embedding
        coordinates to start training from, instead of a random
        initialization. When geometry="sphere", this is treated as an
        already-fit *Euclidean* embedding and is projected onto the sphere
        directly, skipping the internal warm-start Euclidean fit described
        above -- useful when that Euclidean embedding has already been
        computed elsewhere. When geometry="euclidean", it is used directly
        as the starting point for the fit.

    Returns:
    best_embedding, lowest_loss, epoch_stopped, counter, history
    where history is a DataFrame with columns:
        epoch, train_loss, test_loss, train_acc, test_acc
    """
    if geometry not in ("euclidean", "sphere"):
        raise ValueError(f"geometry must be 'euclidean' or 'sphere', got {geometry!r}")

    if random_state is not None:
        np.random.seed(random_state)
        torch.manual_seed(random_state)

    n = int(max(X_train.max(), X_test.max()) + 1)  # number of targets

    if warm_start is not None:
        warm_start = np.asarray(warm_start, dtype="float32")
        if warm_start.shape != (n, d):
            raise ValueError(
                f"warm_start must have shape ({n}, {d}), got {warm_start.shape}"
            )

    if geometry == "sphere":
        if warm_start is not None:
            euclidean_embedding = warm_start
        else:
            euclidean_embedding, *_ = _fit_offline(
                X_train, X_test, n=n, d=d, max_epochs=max_epochs, tolerance=tolerance,
                tol_window=tol_window, print_every=max_epochs, device=device,
                noise_model="CKL", random_state=random_state,
                stage_label="[spherical warm start: fitting free Euclidean embedding]",
            )
        norms = np.linalg.norm(euclidean_embedding, axis=1, keepdims=True)
        norms[norms == 0] = 1.0
        start_embedding = (radius * euclidean_embedding / norms).astype("float32")
    else:
        start_embedding = warm_start

    noise_model = "CKL" if geometry == "euclidean" else "SphericalCKL"
    module_kwargs = {} if geometry == "euclidean" else {"module__radius": radius}
    stage_label = "[fitting constrained spherical embedding]" if geometry == "sphere" else None

    return _fit_offline(
        X_train, X_test, n=n, d=d, max_epochs=max_epochs, tolerance=tolerance,
        tol_window=tol_window, print_every=print_every, device=device,
        noise_model=noise_model, embedding=start_embedding, random_state=random_state,
        module_kwargs=module_kwargs, stage_label=stage_label,
    )


def process_all_workers(input_file, additional_data_file, output_dir,
                        d=5, max_epochs=50_000, tolerance=1e-4, tol_window=10_000, device=None,
                        geometry="euclidean", radius=1.0):
    """
    Process triplets for all workers from a single CSV file and append additional data.

    Parameters:
    input_file: path to input CSV containing all triplets with columns:
                worker_id, head, winner, loser, sampleSet
    additional_data_file: path to CSV containing item metadata to append
                          (rows should correspond to items in index order)
    output_dir: directory to save output CSV files
    d: embedding dimensions (default 5)
    max_epochs: maximum training epochs (default 50,000)
    tolerance: loss tolerance for early stopping (default 1e-4)
    tol_window: epochs without improvement before early stopping triggers (default 10,000)
    geometry: "euclidean" (default) or "sphere". See train_embedding_model().
    radius: radius of the sphere when geometry="sphere". Ignored otherwise.

    Output files written to output_dir:
        model_history.csv       -- training history per worker
        embeddings_group.csv    -- group-level embedding only
        embeddings.csv          -- all per-worker and group embeddings concatenated
    """
    os.makedirs(output_dir, exist_ok=True)

    df = pd.read_csv(input_file)
    additional_data = pd.read_csv(additional_data_file)
    if "Unnamed: 0" in additional_data.columns:
        additional_data = additional_data.rename(columns={"Unnamed: 0": "index"})

    model_history = []
    all_embeddings = []

    for worker_id in df['worker_id'].unique():
        print(f"Processing worker_id: {worker_id}")

        worker_df = df[df['worker_id'] == worker_id]

        train_data = worker_df[worker_df['sampleSet'] == 'train']
        test_data  = worker_df[worker_df['sampleSet'] == 'test']

        if len(train_data) == 0 or len(test_data) == 0:
            print(f"Skipping worker_id {worker_id} - insufficient train/test data")
            continue

        X_train = train_data[["head", "winner", "loser"]].to_numpy()
        X_test  = test_data[["head",  "winner", "loser"]].to_numpy()

        embedding, loss, epoch, counter, _ = train_embedding_model(
            X_train, X_test, d=d, max_epochs=max_epochs,
            tolerance=tolerance, tol_window=tol_window, device=device,
            geometry=geometry, radius=radius,
        )

        emb_df = pd.DataFrame(embedding, columns=[f'dim_{i}' for i in range(embedding.shape[1])])
        emb_df['worker_id'] = worker_id

        for column in additional_data.columns:
            emb_df[column] = additional_data[column].values[:len(emb_df)]

        all_embeddings.append(emb_df)

        history_entry = {
            "worker_id":              worker_id,
            "lowest_loss":            loss,
            "epoch":                  epoch,
            "counter_from_last_update": counter,
            "n_train_triplets":       len(train_data),
            "n_test_triplets":        len(test_data),
        }
        model_history.append(history_entry)

        history_df = pd.DataFrame(model_history)
        history_df.to_csv(os.path.join(output_dir, "model_history.csv"), index=False)

    # Group-level embedding across all workers
    print("Processing group-level embedding across all workers...")
    group_train = df[df['sampleSet'] == 'train'] if 'sampleSet' in df.columns else df
    group_test  = df[df['sampleSet'] == 'test']  if 'sampleSet' in df.columns else pd.DataFrame()

    if len(group_train) == 0 or len(group_test) == 0:
        shuffled  = df.sample(frac=1.0, random_state=42)
        split_idx = int(0.7 * len(shuffled)) if len(shuffled) > 0 else 0
        group_train = shuffled.iloc[:split_idx]
        group_test  = shuffled.iloc[split_idx:]

    if len(group_train) > 0 and len(group_test) > 0:
        X_train_group = group_train[["head", "winner", "loser"]].to_numpy()
        X_test_group  = group_test[["head",  "winner", "loser"]].to_numpy()

        emb_group, loss_group, epoch_group, counter_group, _ = train_embedding_model(
            X_train_group, X_test_group, d=d, max_epochs=max_epochs,
            tolerance=tolerance, tol_window=tol_window, device=device,
            geometry=geometry, radius=radius,
        )

        emb_group_df = pd.DataFrame(emb_group, columns=[f'dim_{i}' for i in range(emb_group.shape[1])])
        emb_group_df['worker_id'] = 'group'

        for column in additional_data.columns:
            emb_group_df[column] = additional_data[column].values[:len(emb_group_df)]

        all_embeddings.append(emb_group_df)

        history_entry = {
            "worker_id":              'group',
            "lowest_loss":            loss_group,
            "epoch":                  epoch_group,
            "counter_from_last_update": counter_group,
            "n_train_triplets":       len(group_train),
            "n_test_triplets":        len(group_test),
        }
        model_history.append(history_entry)

        emb_group_df.to_csv(os.path.join(output_dir, "embeddings_group.csv"), index=False)

    history_df = pd.DataFrame(model_history)
    history_df.to_csv(os.path.join(output_dir, "model_history.csv"), index=False)

    consolidated_embeddings = pd.concat(all_embeddings, ignore_index=True)
    consolidated_embeddings.to_csv(os.path.join(output_dir, "embeddings.csv"), index=False)

    return history_df, consolidated_embeddings
