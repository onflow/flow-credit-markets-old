## Spec: Flow Yield Vaults Early Access

### High-Level Intention
Gate all Vault Position interactions to a manually approved allowlist. Access is strictly granted only if the **Signer is allowed**. This permission is tied to the signer's identity and cannot be shared or transferred, even if the Vault resource itself moves.

### Primitives & Notation
* **$E$**: The set of addresses with Early Access (the "Allowlist").
* **$s$**: The transaction signer address.
* **$V$**: A Vault Position resource.
* **$Cap(s, V)$**: A boolean representing if $s$ has a valid Cadence-level right to $V$ (meaning $s$ is the **Owner** OR holds a **Capability**).
* **$op(s, V)$**: Signer $s$ attempting an operation (Deposit/Withdraw) on $V$.

---

### Precise Logic
For any operation $op(s, V)$, the system must assert:

$$(s \in E) \wedge Cap(s, V)$$

If this condition is **false**, the transaction must **panic**.

---

### Case Matrix
**Assumptions:**
* $A \in E$ (Authorized)
* $B \notin E$ (Unauthorized)
* $Cap(A, V_1)$ is true
* $Cap(B, V_2)$ is true

| Action | Result | Requirement Failed |
| :--- | :--- | :--- |
| $op(A, V_1)$ | **OK** | None |
| $op(A, V_2)$ | **Abort** | $\neg Cap(A, V_2)$ |
| $op(B, V_1)$ | **Abort** | $s \notin E \wedge \neg Cap(B, V_1)$ |
| $op(B, V_2)$ | **Abort** | $s \notin E$ |

---

### Implementation Notes
* **Storage:** $E$ is represented by `map: {Address: Bool}`.
* **Entry Point:** Checked via `fun protectedFunction(signer: &Account)`.
