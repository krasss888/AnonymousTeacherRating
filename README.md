# Anonymous Teacher Rating · Zama FHE

A minimalist dApp demonstrating **anonymous teacher evaluations** on the **Zama FHEVM**. Students submit **encrypted ratings**; only aggregate results (sum & count) are decryptable for the public so anyone can compute an average. Individual ratings remain private end‑to‑end.

> **Network:** Sepolia
> **Contract Address:** `0xDF3920F9500C29F6e8e1441f53A6d572c134Fce2`
> **Relayer SDK:** `@zama-fhe/relayer-sdk-js` **0.2.0**
> **Frontend entry:** `frontend/public/index.html`

---

## ✨ Features

* **Private input** — Ratings encrypted in the browser using Zama Relayer SDK; ciphertext handles are the only thing sent on‑chain.
* **Public aggregates** — Contract stores encrypted `sum` and `count`; owner can mark them as publicly decryptable.
* **Dual decryption flows** — The UI first tries `publicDecrypt`, then gracefully falls back to `userDecrypt` (EIP‑712 signature) if needed.
* **Clear developer logs** — Rich console logs for encryption/decryption (`[FHE] encrypt`, `decrypt(public)`, `decrypt(user)`) with timings and sizes.
* **Owner tools** — Add teachers, ensure aggregates are public, basic checks to prevent on‑chain reverts.
* **No 3rd‑party icon packs** — CSP and runtime guards block unwanted external CSS (e.g., font‑awesome) to avoid SRI warnings.

---

## 🧱 Architecture

* **Solidity (FHEVM)** — Uses Zama's official Solidity library for encrypted types/ops. Aggregates are kept as encrypted integers.
* **Relayer SDK (0.2.0)** — Handles client‑side encryption and decryption (public & user), plus proof generation.
* **Frontend** — A single static page (`frontend/public/index.html`) with vanilla JS + Ethers v6.

```
Browser (Relayer SDK)
   ├─► encrypt rating → handles + proof
   ├─► tx submitRating(id, handle, proof)
   └─► (Later) publicDecrypt / userDecrypt(sum, count) → average
```

---

## 🧩 Main UI Actions

* **Submit a Private Rating**

  * Choose `Teacher ID` and a `Score` within the configured range (default 1..10).
  * Client encrypts with `createEncryptedInput(...).add8(score).encrypt()` and sends `(handle, proof)` on‑chain.

* **View Public Average**

  * Fetches encrypted `sum` and `count` handles from the contract.
  * Attempts `publicDecrypt([sumH, countH])`; falls back to `userDecrypt(...)` if needed.
  * Displays average and a simple meter.

* **Owner Tools**

  * **Add Teacher**: `addTeacher(id, name)`.
  * **Ensure Public**: `ensurePublic(id)` marks aggregates as publicly decryptable for the given teacher.

---

## 📦 Prerequisites

* Node.js 18+ and a static file server (e.g., `serve`, `http-server`, `vite preview`).
* MetaMask (or any EIP‑1193 provider) connected to **Sepolia**.

---

## 🚀 Quick Start

1. **Clone**

   ```bash
   git clone <your-repo-url>
   cd <your-repo>/frontend/public
   ```

2. **Install a simple static server** (choose one):

   ```bash
   npm i -g serve            # or
   npm i -g http-server      # or
   npm i -g vite
   ```

3. **Run**

   ```bash
   # if using serve
   serve -l 5173 .

   # or http-server
   http-server -p 5173 .

   # or vite (no build; just preview a static dir)
   vite preview --port 5173 --strictPort
   ```

4. **Open** `http://localhost:5173/` and click **Connect Wallet**.

> The page sources the Relayer SDK from the Zama CDN and Ethers v6 from jsDelivr; nothing to build.

---

## ⚙️ Configuration

* **Contract address** — defined at the top of `index.html`:

  ```js
  const CONTRACT_ADDRESS = "0xDF3920F9500C29F6e8e1441f53A6d572c134Fce2";
  ```
* **Relayer** — default:

  ```js
  const RELAYER_URL = "https://relayer.testnet.zama.cloud";
  // SDK imports from: https://cdn.zama.ai/relayer-sdk-js/0.2.0/relayer-sdk-js.js
  ```
* **Rating bounds** — UI reads `minRating()`/`maxRating()` from the contract if available; otherwise defaults to `1..10`.

---

## 🔐 How It Works (FHE Flow)

1. **Encrypt rating in the browser**

   ```js
   const buf = relayer.createEncryptedInput(CONTRACT_ADDRESS, user);
   buf.add8(score); // score ∈ [1..10]
   const { handles, inputProof } = await buf.encrypt();
   // handles[0] and inputProof go to the contract
   ```
2. **Submit on‑chain**

   ```js
   await contract.submitRating(teacherId, handles[0], inputProof);
   ```
3. **Decrypt aggregates**

   * Try `publicDecrypt([sumH, countH])` first.
   * If not public, use `userDecrypt(...)` with an **EIP‑712** signature for private read access.

---

## 🧪 Developer Console Logs

The UI prints detailed logs grouped under:

* **`[FHE] encrypt → createInput`** — added values, proof size, first handle preview, timing.
* **`[FHE] decrypt(public)`** — output format (array/object) and timing.
* **`[FHE] decrypt(user)`** — EIP‑712 signature preview, decrypted keys, timing.
* **`[FHE] average`** — final `sum`, `count`, computed `avg`.

You can toggle verbosity by changing `const DEBUG = true` (still prints the FHE groups).

---

## 🧯 Troubleshooting

* **MetaMask – `execution reverted`**

  * Verify the `Teacher ID` exists before submitting (the UI checks via `teacherExists(id)`; ensure you pressed **Fetch** or used a valid ID).
  * Owner‑only actions (add teacher / ensure public) require the owner account.

* **Blocked font‑awesome / SRI warnings**

  * The page intentionally blocks `cdnjs/font-awesome` via CSP + a runtime guard to prevent integrity warnings and noisy logs.

* **Sepolia switch fails**

  * MetaMask should prompt to switch. If not, add Sepolia manually (chainId `0xaa36a7`).

* **Relayer errors**

  * Ensure you’re online and can reach `https://relayer.testnet.zama.cloud`.
  * If public decrypt fails, the UI auto‑tries user decrypt (sign a message).

---

## 📁 Project Layout

```
repo-root/
└─ frontend/
   └─ public/
      └─ index.html     # Single‑file UI (no build step required)
```

If you later adopt a bundler (Vite/Next), keep the Relayer SDK version to **0.2.0** and **do not** import deprecated packages such as `@fhevm-js/relayer`.

---

## 🛡️ Security Notes

* Uses **only** Zama’s official libraries and documented Relayer SDK flows.
* Avoid FHE operations in `view/pure` functions on-chain.
* `euint256`/`eaddress` restrictions: arithmetic is unsupported; use comparisons/bitwise ops only.
* Prefer granting decryption rights purposefully (`makePubliclyDecryptable` for aggregates; `userDecrypt` for private reads).

---

## 📝 License

MIT — see `LICENSE` (or adapt as needed).


