-- GrapheneTrace Database Initialization Script
-- Creates tables for pressure monitoring data with user management

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- USER MANAGEMENT TABLES
-- ============================================================

-- Users table - stores all users (admin, clinician, patient)
CREATE TABLE IF NOT EXISTS users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    user_type VARCHAR(20) NOT NULL CHECK (user_type IN ('admin', 'clinician', 'patient')),
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Clinician-Patient relationship (many-to-many)
CREATE TABLE IF NOT EXISTS clinician_patients (
    clinician_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    patient_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('pending', 'active', 'inactive')),
    PRIMARY KEY (clinician_id, patient_id)
);

-- Patient Settings - per-patient alert thresholds
CREATE TABLE IF NOT EXISTS patient_settings (
    patient_id UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    low_pressure_threshold SMALLINT DEFAULT 50 CHECK (low_pressure_threshold >= 1 AND low_pressure_threshold <= 255),
    high_pressure_threshold SMALLINT DEFAULT 200 CHECK (high_pressure_threshold >= 1 AND high_pressure_threshold <= 255),
    alert_enabled BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- DEVICE MANAGEMENT TABLES
-- ============================================================

-- Devices - physical pressure sensor devices that can be reassigned
CREATE TABLE IF NOT EXISTS devices (
    device_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    serial_number VARCHAR(100) UNIQUE NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    firmware_version VARCHAR(50),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'maintenance', 'decommissioned')),
    last_calibration_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Device Assignments - tracks which patient is assigned to which device over time
CREATE TABLE IF NOT EXISTS device_assignments (
    assignment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id UUID REFERENCES devices(device_id) ON DELETE CASCADE,
    patient_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    unassigned_at TIMESTAMP WITH TIME ZONE,  -- NULL means currently assigned
    assigned_by_user_id UUID REFERENCES users(user_id) ON DELETE SET NULL,
    notes TEXT
);

-- ============================================================
-- SENSOR DATA TABLES
-- ============================================================

-- Sensor Data Sessions - logical groupings of readings from a device
CREATE TABLE IF NOT EXISTS sensor_data_sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id UUID REFERENCES devices(device_id) ON DELETE CASCADE,
    patient_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    session_type VARCHAR(30) DEFAULT 'continuous_monitoring' CHECK (session_type IN ('continuous_monitoring', 'clinical_test', 'calibration', 'demo_import')),
    source_file_path VARCHAR(500),  -- Optional: tracks CSV source for imported demo data
    start_timestamp TIMESTAMP WITH TIME ZONE,
    end_timestamp TIMESTAMP WITH TIME ZONE,  -- NULL means session is still active
    frame_count INTEGER DEFAULT 0,
    frames_per_second DECIMAL(5,2) DEFAULT 1.0,
    is_active BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Raw Pressure Frames - stores all timestamped pressure readings (primary data store)
-- This is the authoritative source for all pressure data, whether from live sensors or imported CSVs
CREATE TABLE IF NOT EXISTS raw_pressure_frames (
    frame_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID REFERENCES sensor_data_sessions(session_id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(device_id) ON DELETE CASCADE,
    patient_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    frame_data JSONB NOT NULL,  -- 32x32 matrix stored as JSON
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- NOTE: device_id is technically redundant (can be retrieved via session_id → sensor_data_sessions → device_id)
    -- However, it's included here for these important reasons:
    -- 1. Device fault analysis: Enables fast queries like "find all readings from faulty device X" without joining through sessions
    -- 2. Data integrity: If a device is found to be malfunctioning, can flag/delete ALL its readings across multiple sessions
    -- 3. Query performance: Avoids expensive joins for device-based filtering (common in QA and calibration workflows)
    -- 4. Audit trail: Preserves device information even if session records are modified or deleted (with ON DELETE CASCADE disabled in future)
    CONSTRAINT frames_device_session_match
        CHECK (device_id IS NOT NULL OR session_id IS NOT NULL)  -- Ensures at least one is populated
);

-- Pressure Metrics - cached computed metrics from frames
CREATE TABLE IF NOT EXISTS pressure_metrics (
    metric_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID REFERENCES sensor_data_sessions(session_id) ON DELETE CASCADE,
    patient_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    source_frame_id UUID REFERENCES raw_pressure_frames(frame_id) ON DELETE SET NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    peak_pressure_index SMALLINT CHECK (peak_pressure_index >= 1 AND peak_pressure_index <= 255),
    contact_area_percentage DECIMAL(5,2) CHECK (contact_area_percentage >= 0 AND contact_area_percentage <= 100),
    max_pressure_coords JSONB,  -- {x: int, y: int}
    processing_status VARCHAR(20) DEFAULT 'computed' CHECK (processing_status IN ('pending', 'computed', 'failed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- ALERTS TABLE
-- ============================================================

-- Alerts - generated when thresholds are exceeded
CREATE TABLE IF NOT EXISTS alerts (
    alert_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    metric_id UUID REFERENCES pressure_metrics(metric_id) ON DELETE CASCADE,
    alert_type VARCHAR(50) NOT NULL DEFAULT 'HIGH_PRESSURE',
    threshold_exceeded SMALLINT NOT NULL,
    actual_value SMALLINT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    acknowledged_by_clinician_id UUID REFERENCES users(user_id) ON DELETE SET NULL
);

-- ============================================================
-- COMMENTS & REPLIES TABLES
-- ============================================================

-- Comments - patient comments on specific timestamps
CREATE TABLE IF NOT EXISTS comments (
    comment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    metric_id UUID REFERENCES pressure_metrics(metric_id) ON DELETE CASCADE,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    comment_text TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Comment Replies - clinician responses to patient comments
CREATE TABLE IF NOT EXISTS comment_replies (
    reply_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    comment_id UUID REFERENCES comments(comment_id) ON DELETE CASCADE,
    clinician_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    reply_text TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================

-- User indexes
CREATE INDEX IF NOT EXISTS idx_users_user_type ON users(user_type);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Clinician-Patient indexes
CREATE INDEX IF NOT EXISTS idx_clinician_patients_clinician ON clinician_patients(clinician_id);
CREATE INDEX IF NOT EXISTS idx_clinician_patients_patient ON clinician_patients(patient_id);

-- Device indexes
CREATE INDEX IF NOT EXISTS idx_devices_serial_number ON devices(serial_number);
CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);

-- Device Assignment indexes
CREATE INDEX IF NOT EXISTS idx_device_assignments_device ON device_assignments(device_id);
CREATE INDEX IF NOT EXISTS idx_device_assignments_patient ON device_assignments(patient_id);
CREATE INDEX IF NOT EXISTS idx_device_assignments_current ON device_assignments(unassigned_at) WHERE unassigned_at IS NULL;

-- Session indexes
CREATE INDEX IF NOT EXISTS idx_sessions_device ON sensor_data_sessions(device_id);
CREATE INDEX IF NOT EXISTS idx_sessions_patient ON sensor_data_sessions(patient_id);
CREATE INDEX IF NOT EXISTS idx_sessions_start_time ON sensor_data_sessions(start_timestamp);
CREATE INDEX IF NOT EXISTS idx_sessions_active ON sensor_data_sessions(is_active);

-- Frame indexes
CREATE INDEX IF NOT EXISTS idx_frames_session ON raw_pressure_frames(session_id);
CREATE INDEX IF NOT EXISTS idx_frames_device ON raw_pressure_frames(device_id);
CREATE INDEX IF NOT EXISTS idx_frames_patient ON raw_pressure_frames(patient_id);
CREATE INDEX IF NOT EXISTS idx_frames_timestamp ON raw_pressure_frames(timestamp);

-- Metrics indexes
CREATE INDEX IF NOT EXISTS idx_metrics_session ON pressure_metrics(session_id);
CREATE INDEX IF NOT EXISTS idx_metrics_patient ON pressure_metrics(patient_id);
CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON pressure_metrics(timestamp);

-- Alerts indexes
CREATE INDEX IF NOT EXISTS idx_alerts_patient ON alerts(patient_id);
CREATE INDEX IF NOT EXISTS idx_alerts_created ON alerts(created_at);
CREATE INDEX IF NOT EXISTS idx_alerts_acknowledged ON alerts(acknowledged_at);

-- Comments indexes
CREATE INDEX IF NOT EXISTS idx_comments_patient ON comments(patient_id);
CREATE INDEX IF NOT EXISTS idx_comments_metric ON comments(metric_id);

-- ============================================================
-- SAMPLE DATA FOR TESTING
-- ============================================================

-- Insert sample admin user (password: admin123 - hashed with bcrypt)
INSERT INTO users (username, password_hash, user_type, email, first_name, last_name)
VALUES
    ('admin', '$2a$11$YourHashHere', 'admin', 'admin@graphenetrace.com', 'Admin', 'User'),
    ('dr_smith', '$2a$11$YourHashHere', 'clinician', 'dr.smith@graphenetrace.com', 'John', 'Smith'),
    ('patient01', '$2a$11$YourHashHere', 'patient', 'patient01@example.com', 'Jane', 'Doe');

-- Setup relationships and sample devices
DO $$
DECLARE
    v_patient_id UUID;
    v_clinician_id UUID;
    v_admin_id UUID;
    v_device_id UUID;
BEGIN
    -- Get user IDs
    SELECT user_id INTO v_patient_id FROM users WHERE username = 'patient01';
    SELECT user_id INTO v_clinician_id FROM users WHERE username = 'dr_smith';
    SELECT user_id INTO v_admin_id FROM users WHERE username = 'admin';

    -- Assign patient to clinician
    INSERT INTO clinician_patients (clinician_id, patient_id, status)
    VALUES (v_clinician_id, v_patient_id, 'active');

    -- Set patient settings
    INSERT INTO patient_settings (patient_id, low_pressure_threshold, high_pressure_threshold)
    VALUES (v_patient_id, 50, 200);

    -- Create sample device
    INSERT INTO devices (serial_number, model_name, firmware_version, status, last_calibration_date)
    VALUES ('SENSORE-2024-001', 'Sensore Pro v2', '1.4.2', 'active', CURRENT_TIMESTAMP - INTERVAL '7 days')
    RETURNING device_id INTO v_device_id;

    -- Assign device to patient
    INSERT INTO device_assignments (device_id, patient_id, assigned_by_user_id, notes)
    VALUES (v_device_id, v_patient_id, v_admin_id, 'Initial device assignment for demo patient');

    -- Create additional demo devices (unassigned)
    INSERT INTO devices (serial_number, model_name, firmware_version, status, last_calibration_date)
    VALUES
        ('SENSORE-2024-002', 'Sensore Pro v2', '1.4.2', 'active', CURRENT_TIMESTAMP - INTERVAL '5 days'),
        ('SENSORE-2023-045', 'Sensore Pro v1', '1.3.8', 'maintenance', CURRENT_TIMESTAMP - INTERVAL '90 days');

END $$;