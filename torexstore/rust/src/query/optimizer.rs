use crate::index::secondary::SecondaryIndex;
use crate::query::condition::{ExecutionPlan, Operator, Query};

/// Query optimizer that selects the best execution plan
///
/// The optimizer analyzes the query and available indexes to determine
/// the most efficient execution strategy:
/// 1. Primary index lookup (O(1)) - for ID-based queries
/// 2. Secondary index scan - for indexed field queries
/// 3. Full collection scan - fallback when no suitable index exists
pub struct QueryOptimizer;

impl QueryOptimizer {
    /// Optimize a query and return the best execution plan
    pub fn optimize(secondary: &SecondaryIndex, collection: &str, query: &Query) -> ExecutionPlan {
        match query {
            Query::All => ExecutionPlan::FullScan,

            Query::Condition(cond) => {
                // Check if we can use a secondary index
                if secondary.has_index(collection, &cond.field) {
                    let index_value = cond.value.to_index_value();
                    let index_value2 = cond.value2.as_ref().map(|v| v.to_index_value());

                    ExecutionPlan::IndexScan {
                        field: cond.field.clone(),
                        operator: cond.operator.clone(),
                        value: index_value,
                        value2: index_value2,
                    }
                } else {
                    // No index available, fall back to full scan
                    ExecutionPlan::FullScan
                }
            }

            Query::And(conditions) => {
                // For AND, try to find the most selective condition with an index
                let mut best_plan: Option<ExecutionPlan> = None;

                for cond in conditions {
                    if let Query::Condition(c) = cond {
                        if secondary.has_index(collection, &c.field) {
                            let plan = ExecutionPlan::IndexScan {
                                field: c.field.clone(),
                                operator: c.operator.clone(),
                                value: c.value.to_index_value(),
                                value2: c.value2.as_ref().map(|v| v.to_index_value()),
                            };

                            // Prefer equality lookups over range scans
                            if best_plan.is_none()
                                || matches!(c.operator, Operator::Equal)
                            {
                                best_plan = Some(plan);
                            }
                        }
                    }
                }

                best_plan.unwrap_or(ExecutionPlan::FullScan)
            }

            Query::Or(_) => {
                // OR conditions typically require full scan unless all branches
                // can use indexes (which is complex to optimize)
                ExecutionPlan::FullScan
            }
        }
    }

    /// Estimate the cost of an execution plan
    ///
    /// Returns a cost estimate where lower is better:
    /// - PrimaryLookup: 1 (constant time)
    /// - IndexScan: estimated number of matching records
    /// - FullScan: total records in collection
    pub fn estimate_cost(plan: &ExecutionPlan, collection_total: usize) -> usize {
        match plan {
            ExecutionPlan::PrimaryLookup { .. } => 1,
            ExecutionPlan::IndexScan { .. } => {
                // Rough estimate: assume index scan is 10x cheaper than full scan
                (collection_total / 10).max(1)
            }
            ExecutionPlan::FullScan => collection_total,
        }
    }
}
