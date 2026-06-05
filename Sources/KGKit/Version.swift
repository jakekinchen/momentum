/// On-device FitGraph KG runtime. Version stamps are frozen by the build-time
/// canonical layer and carried in every DecisionReceipt for provenance.
/// Mirrors GRAPH_VERSION / RULESET_VERSION (kg/validation.py) and
/// ONTOLOGY_LOCK_VERSION (kg/safety.py).
public enum KGVersion {
    public static let graphVersion = "fitgraph-kg-m5-validation-v0"
    public static let rulesetVersion = "ruleset-m2-safety-v0"
    public static let ontologyLockVersion = "ontology-lock-m0-unverified"
}
