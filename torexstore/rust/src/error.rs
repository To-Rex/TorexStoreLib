use std::fmt;

/// Database error types
#[derive(Debug)]
pub enum StoreError {
    /// IO error during file operations
    Io(std::io::Error),
    /// Record not found
    NotFound(String),
    /// Collection not found
    CollectionNotFound(String),
    /// Invalid operation
    InvalidOperation(String),
    /// Serialization/deserialization error
    Serialization(String),
    /// Database is closed
    Closed,
    /// Invalid record format
    InvalidFormat(String),
    /// Index error
    IndexError(String),
}

impl fmt::Display for StoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            StoreError::Io(e) => write!(f, "IO error: {}", e),
            StoreError::NotFound(id) => write!(f, "Record not found: {}", id),
            StoreError::CollectionNotFound(c) => write!(f, "Collection not found: {}", c),
            StoreError::InvalidOperation(msg) => write!(f, "Invalid operation: {}", msg),
            StoreError::Serialization(msg) => write!(f, "Serialization error: {}", msg),
            StoreError::Closed => write!(f, "Database is closed"),
            StoreError::InvalidFormat(msg) => write!(f, "Invalid format: {}", msg),
            StoreError::IndexError(msg) => write!(f, "Index error: {}", msg),
        }
    }
}

impl std::error::Error for StoreError {}

impl From<std::io::Error> for StoreError {
    fn from(e: std::io::Error) -> Self {
        StoreError::Io(e)
    }
}

impl From<bincode::Error> for StoreError {
    fn from(e: bincode::Error) -> Self {
        StoreError::Serialization(e.to_string())
    }
}

pub type StoreResult<T> = Result<T, StoreError>;
