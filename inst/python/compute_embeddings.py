import pandas as pd
import numpy as np
import random
from salmon.triplets.offline import OfflineEmbedding
import os


def train_embedding_model(X_train, X_test, d=5, max_epochs=50_000, tolerance=1e-4, tol_window=10_000, print_every=100):
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

    Returns:
    best_embedding, lowest_loss, epoch_stopped, counter, history
    where history is a DataFrame with columns:
        epoch, train_loss, test_loss, train_acc, test_acc
    """
    n = int(max(X_train.max(), X_test.max()) + 1)  # number of targets

    model = OfflineEmbedding(n=n, d=d, max_epochs=max_epochs, verbose=100)
    model.partial_fit(X_train)

    current_lowest_loss = 1
    current_best_embedding = model.embedding_
    counter_since_update = 0
    epoch_history = []

    header = f"{'Epoch':>8}  {'Train Loss':>10}  {'Test Loss':>10}  {'Train Acc':>10}  {'Test Acc':>10}"
    print(header)
    print("-" * len(header))

    for epoch in range(max_epochs):
        model.partial_fit(X_train)

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
        elif (current_lowest_loss - test_loss) < tolerance and counter_since_update > tol_window:
            print(f"{epoch:>8}  {train_loss:>10.4f}  {test_loss:>10.4f}  {train_acc:>10.4f}  {test_acc:>10.4f}  [early stop]")
            break
        else:
            counter_since_update += 1

    history = pd.DataFrame(epoch_history)
    return current_best_embedding, current_lowest_loss, epoch, counter_since_update, history


def process_all_workers(input_file, additional_data_file, output_dir,
                        d=5, max_epochs=50_000, tolerance=1e-4, tol_window=10_000):
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
            tolerance=tolerance, tol_window=tol_window
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
            tolerance=tolerance, tol_window=tol_window
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
