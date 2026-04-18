1.  **Refactor `deduplicatedIntersections`:**
    -   **Target:** `FormationFlow/Models.swift`
    -   **What:** The `deduplicatedIntersections` function currently uses a `.reduce(into:)` with a nested `.contains` scan, resulting in $O(N^2)$ complexity.
    -   **How:** Replace the O(N^2) `.reduce` block with a spatial grid deduplication algorithm, improving complexity to $O(N)$. I'll use a `var grid: [Int: [CGPoint]]` where the key is based on the x and y cell indices.

2.  **Complete pre-commit steps to ensure proper testing, verification, review, and reflection are done.**
    -   Run tests (if applicable) and perform any necessary pre-commit hooks to guarantee the changes don't break existing functionality.

3.  **Submit PR:**
    -   Submit the pull request detailing the optimization for review.
