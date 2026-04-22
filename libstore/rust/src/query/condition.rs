use serde::{Deserialize, Serialize};

use crate::index::secondary::IndexValue;

/// Comparison operators for query conditions
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Operator {
    Equal,
    NotEqual,
    GreaterThan,
    LessThan,
    GreaterThanOrEqual,
    LessThanOrEqual,
    Range,
}

/// A single query condition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Condition {
    /// Field name to compare
    pub field: String,
    /// Comparison operator
    pub operator: Operator,
    /// Value to compare against
    pub value: QueryValue,
    /// Optional second value for range queries
    pub value2: Option<QueryValue>,
}

/// Query value types
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum QueryValue {
    String(String),
    Integer(i64),
    Float(f64),
    Boolean(bool),
    Null,
}

impl QueryValue {
    /// Convert to an IndexValue for secondary index lookups
    pub fn to_index_value(&self) -> IndexValue {
        match self {
            QueryValue::String(s) => IndexValue::from_string(s),
            QueryValue::Integer(i) => IndexValue::from_int(*i),
            QueryValue::Float(f) => IndexValue::from_float(*f),
            QueryValue::Boolean(b) => IndexValue::from_bool(*b),
            QueryValue::Null => IndexValue::Null,
        }
    }
}

/// Logical combinator for multiple conditions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Query {
    /// Match all conditions (AND)
    And(Vec<Query>),
    /// Match any condition (OR)
    Or(Vec<Query>),
    /// Single condition
    Condition(Condition),
    /// Match all
    All,
}

impl Query {
    /// Create an equality condition
    pub fn eq(field: &str, value: QueryValue) -> Self {
        Query::Condition(Condition {
            field: field.to_string(),
            operator: Operator::Equal,
            value,
            value2: None,
        })
    }

    /// Create a not-equal condition
    pub fn ne(field: &str, value: QueryValue) -> Self {
        Query::Condition(Condition {
            field: field.to_string(),
            operator: Operator::NotEqual,
            value,
            value2: None,
        })
    }

    /// Create a greater-than condition
    pub fn gt(field: &str, value: QueryValue) -> Self {
        Query::Condition(Condition {
            field: field.to_string(),
            operator: Operator::GreaterThan,
            value,
            value2: None,
        })
    }

    /// Create a less-than condition
    pub fn lt(field: &str, value: QueryValue) -> Self {
        Query::Condition(Condition {
            field: field.to_string(),
            operator: Operator::LessThan,
            value,
            value2: None,
        })
    }

    /// Create a greater-than-or-equal condition
    pub fn gte(field: &str, value: QueryValue) -> Self {
        Query::Condition(Condition {
            field: field.to_string(),
            operator: Operator::GreaterThanOrEqual,
            value,
            value2: None,
        })
    }

    /// Create a less-than-or-equal condition
    pub fn lte(field: &str, value: QueryValue) -> Self {
        Query::Condition(Condition {
            field: field.to_string(),
            operator: Operator::LessThanOrEqual,
            value,
            value2: None,
        })
    }

    /// Create a range condition
    pub fn range(field: &str, start: QueryValue, end: QueryValue) -> Self {
        Query::Condition(Condition {
            field: field.to_string(),
            operator: Operator::Range,
            value: start,
            value2: Some(end),
        })
    }

    /// Combine queries with AND
    pub fn and(queries: Vec<Query>) -> Self {
        Query::And(queries)
    }

    /// Combine queries with OR
    pub fn or(queries: Vec<Query>) -> Self {
        Query::Or(queries)
    }

    /// Match all records
    pub fn all() -> Self {
        Query::All
    }
}

/// Query execution plan
#[derive(Debug, Clone)]
pub enum ExecutionPlan {
    /// Use primary index for direct lookup
    PrimaryLookup { id: String },
    /// Use secondary index for field-based lookup
    IndexScan {
        field: String,
        operator: Operator,
        value: IndexValue,
        value2: Option<IndexValue>,
    },
    /// Full collection scan
    FullScan,
}
