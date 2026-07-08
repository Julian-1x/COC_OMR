<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('teacher_profiles', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreign('id')->references('id')->on('users')->cascadeOnDelete();
            $table->string('full_name');
            $table->string('role')->default('teacher');
            $table->boolean('is_active')->default(true);
            $table->string('school_name')->nullable();
            $table->text('pin_hash')->nullable();
            $table->text('pin_salt')->nullable();
            $table->timestamps();
        });

        Schema::create('sections', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('owner_teacher_id')->constrained('users')->cascadeOnDelete();
            $table->string('name');
            $table->string('teacher')->nullable();
            $table->integer('student_count')->nullable();
            $table->string('school_year')->nullable();
            $table->string('term_label')->nullable();
            $table->timestamp('archived_at')->nullable();
            $table->string('local_id')->nullable();
            $table->string('sync_status')->default('synced');
            $table->timestamps();

            $table->unique(['owner_teacher_id', 'name']);
            $table->index(['owner_teacher_id', 'archived_at']);
            $table->index(['owner_teacher_id', 'school_year']);
        });

        Schema::create('subjects', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('owner_teacher_id')->constrained('users')->cascadeOnDelete();
            $table->string('local_id');
            $table->string('name');
            $table->json('answer_key');
            $table->integer('total_questions');
            $table->json('section_names')->nullable();
            $table->json('section_qr_data')->default('{}');
            $table->date('exam_date')->nullable();
            $table->integer('passing_score');
            $table->boolean('use_partial_credit')->default(false);
            $table->string('sync_status')->default('synced');
            $table->timestamps();

            $table->unique(['owner_teacher_id', 'local_id']);
            $table->index(['owner_teacher_id', 'name']);
        });

        Schema::create('students', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('owner_teacher_id')->constrained('users')->cascadeOnDelete();
            $table->string('school_id');
            $table->string('omr_id');
            $table->string('name');
            $table->string('section_name');
            $table->decimal('score', 10, 4)->nullable();
            $table->json('answers')->nullable();
            $table->timestamp('scan_date')->nullable();
            $table->decimal('confidence', 10, 4)->nullable();
            $table->string('local_id')->nullable();
            $table->string('sync_status')->default('synced');
            $table->timestamps();

            $table->unique(['owner_teacher_id', 'omr_id']);
            $table->unique(['owner_teacher_id', 'school_id']);
            $table->index(['owner_teacher_id', 'section_name']);
        });

        Schema::create('scan_results', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('owner_teacher_id')->constrained('users')->cascadeOnDelete();
            $table->string('student_omr_id');
            $table->foreignUuid('subject_id')->nullable()->constrained('subjects')->nullOnDelete();
            $table->string('subject_local_id')->nullable();
            $table->string('subject_name');
            $table->string('sheet_id')->nullable();
            $table->json('detected_answers');
            $table->json('correctness_map');
            $table->decimal('score', 10, 4);
            $table->integer('total_questions');
            $table->decimal('confidence', 10, 4);
            $table->timestamp('scan_time');
            $table->string('scanned_image_path')->nullable();
            $table->json('review_reasons')->nullable();
            $table->json('flagged_questions')->nullable();
            $table->boolean('manually_confirmed')->default(false);
            $table->boolean('needs_review')->default(false);
            $table->string('local_id')->nullable();
            $table->string('sync_status')->default('synced');
            $table->timestamps();

            $table->unique(['owner_teacher_id', 'student_omr_id', 'subject_local_id', 'scan_time'], 'scan_results_owner_student_subject_time_unique');
            $table->index(['owner_teacher_id', 'student_omr_id']);
            $table->index(['owner_teacher_id', 'subject_local_id']);
            $table->index(['owner_teacher_id', 'local_id']);
        });

        Schema::create('deadlines', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('owner_teacher_id')->constrained('users')->cascadeOnDelete();
            $table->string('local_id');
            $table->string('title');
            $table->string('section_name')->nullable();
            $table->foreignUuid('subject_id')->nullable()->constrained('subjects')->cascadeOnDelete();
            $table->string('subject_local_id')->nullable();
            $table->timestamp('due_date');
            $table->boolean('is_completed')->default(false);
            $table->string('sync_status')->default('synced');
            $table->timestamps();

            $table->unique(['owner_teacher_id', 'local_id']);
            $table->index(['owner_teacher_id', 'due_date']);
        });

        Schema::create('scan_warnings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('owner_teacher_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('scan_result_id')->nullable()->constrained('scan_results')->cascadeOnDelete();
            $table->integer('question_number')->nullable();
            $table->string('reason');
            $table->json('metadata')->nullable();
            $table->timestamp('created_at')->useCurrent();
        });

        Schema::create('app_releases', function (Blueprint $table) {
            $table->id();
            $table->integer('build_number');
            $table->string('version_name');
            $table->string('download_url')->nullable();
            $table->text('notes')->nullable();
            $table->boolean('mandatory')->default(false);
            $table->timestamp('created_at')->useCurrent();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('app_releases');
        Schema::dropIfExists('scan_warnings');
        Schema::dropIfExists('deadlines');
        Schema::dropIfExists('scan_results');
        Schema::dropIfExists('students');
        Schema::dropIfExists('subjects');
        Schema::dropIfExists('sections');
        Schema::dropIfExists('teacher_profiles');
    }
};
