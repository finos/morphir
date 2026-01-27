//! Sample data for demonstration purposes.

use crate::models::{Model, ModelType, Project, SearchResult, Workspace};

pub fn sample_workspaces() -> Vec<Workspace> {
    vec![
        Workspace {
            id: "ws-1".to_string(),
            name: "Finance Domain".to_string(),
            description: "Core financial modeling domain including accounts, transactions, and reporting models.".to_string(),
            project_count: 5,
            is_favorite: true,
            last_accessed: Some(1706300000),
        },
        Workspace {
            id: "ws-2".to_string(),
            name: "Healthcare".to_string(),
            description: "Healthcare domain models for patient records, appointments, and medical billing.".to_string(),
            project_count: 3,
            is_favorite: false,
            last_accessed: Some(1706200000),
        },
        Workspace {
            id: "ws-3".to_string(),
            name: "E-Commerce".to_string(),
            description: "Online retail domain with products, orders, inventory, and customer management.".to_string(),
            project_count: 7,
            is_favorite: true,
            last_accessed: Some(1706100000),
        },
        Workspace {
            id: "ws-4".to_string(),
            name: "Insurance".to_string(),
            description: "Insurance domain covering policies, claims, underwriting, and risk assessment.".to_string(),
            project_count: 4,
            is_favorite: false,
            last_accessed: None,
        },
    ]
}

pub fn sample_projects(workspace_id: &str) -> Vec<Project> {
    match workspace_id {
        "ws-1" => vec![
            Project {
                id: "proj-1".to_string(),
                name: "Account Management".to_string(),
                description: "Core account types and operations for managing financial accounts."
                    .to_string(),
                workspace_id: "ws-1".to_string(),
                model_count: 12,
                is_active: true,
            },
            Project {
                id: "proj-2".to_string(),
                name: "Transaction Processing".to_string(),
                description: "Models for financial transactions, transfers, and settlements."
                    .to_string(),
                workspace_id: "ws-1".to_string(),
                model_count: 8,
                is_active: true,
            },
            Project {
                id: "proj-3".to_string(),
                name: "Reporting".to_string(),
                description: "Financial reporting and analytics models.".to_string(),
                workspace_id: "ws-1".to_string(),
                model_count: 5,
                is_active: false,
            },
        ],
        "ws-2" => vec![
            Project {
                id: "proj-4".to_string(),
                name: "Patient Records".to_string(),
                description: "Electronic health records and patient data models.".to_string(),
                workspace_id: "ws-2".to_string(),
                model_count: 15,
                is_active: true,
            },
            Project {
                id: "proj-5".to_string(),
                name: "Appointments".to_string(),
                description: "Scheduling and appointment management.".to_string(),
                workspace_id: "ws-2".to_string(),
                model_count: 6,
                is_active: true,
            },
        ],
        _ => vec![Project {
            id: "proj-default".to_string(),
            name: "Default Project".to_string(),
            description: "A sample project for this workspace.".to_string(),
            workspace_id: workspace_id.to_string(),
            model_count: 3,
            is_active: true,
        }],
    }
}

pub fn sample_models(project_id: &str) -> Vec<Model> {
    match project_id {
        "proj-1" => vec![
            Model {
                id: "model-1".to_string(),
                name: "Account".to_string(),
                description: "Core account type with balance and status.".to_string(),
                project_id: "proj-1".to_string(),
                model_type: ModelType::TypeDefinition,
                type_count: 5,
                function_count: 0,
            },
            Model {
                id: "model-2".to_string(),
                name: "AccountStatus".to_string(),
                description: "Enumeration of possible account states.".to_string(),
                project_id: "proj-1".to_string(),
                model_type: ModelType::TypeDefinition,
                type_count: 1,
                function_count: 0,
            },
            Model {
                id: "model-3".to_string(),
                name: "openAccount".to_string(),
                description: "Function to create and open a new account.".to_string(),
                project_id: "proj-1".to_string(),
                model_type: ModelType::Function,
                type_count: 0,
                function_count: 1,
            },
            Model {
                id: "model-4".to_string(),
                name: "closeAccount".to_string(),
                description: "Function to close an existing account.".to_string(),
                project_id: "proj-1".to_string(),
                model_type: ModelType::Function,
                type_count: 0,
                function_count: 1,
            },
        ],
        _ => vec![Model {
            id: "model-default".to_string(),
            name: "SampleType".to_string(),
            description: "A sample type definition.".to_string(),
            project_id: project_id.to_string(),
            model_type: ModelType::TypeDefinition,
            type_count: 1,
            function_count: 0,
        }],
    }
}

/// Get all projects across all workspaces.
pub fn all_projects() -> Vec<Project> {
    let workspaces = sample_workspaces();
    workspaces
        .iter()
        .flat_map(|ws| sample_projects(&ws.id))
        .collect()
}

/// Get all models across all projects.
pub fn all_models() -> Vec<Model> {
    let projects = all_projects();
    projects
        .iter()
        .flat_map(|p| sample_models(&p.id))
        .collect()
}

/// Get all items as search results.
pub fn all_search_results() -> Vec<SearchResult> {
    let mut results = Vec::new();

    for ws in sample_workspaces() {
        results.push(SearchResult::Workspace(ws));
    }

    for proj in all_projects() {
        results.push(SearchResult::Project(proj));
    }

    for model in all_models() {
        results.push(SearchResult::Model(model));
    }

    results
}
