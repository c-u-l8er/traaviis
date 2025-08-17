defmodule Mix.Tasks.Storage.Migrate do
  @moduledoc """
  Mix task to migrate TRAAVIIS data to enhanced directory structure.

  Usage:
    mix storage.migrate                    # Run full migration
    mix storage.migrate --backup-only      # Create backup only
    mix storage.migrate --dry-run          # Show what would be migrated
    mix storage.migrate --force            # Skip confirmations
  """

  use Mix.Task
  alias FSMApp.Storage.DirectoryMigrator
  require Logger

  @shortdoc "Migrate TRAAVIIS data to enhanced directory structure"

  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [
      backup_only: :boolean,
      dry_run: :boolean,
      force: :boolean,
      help: :boolean
    ])

    cond do
      opts[:help] -> show_help()
      opts[:backup_only] -> run_backup_only()
      opts[:dry_run] -> run_dry_run()
      true -> run_migration(opts)
    end
  end

  defp show_help do
    IO.puts """
    TRAAVIIS Storage Migration Task

    This task migrates your TRAAVIIS data from the current structure to the
    enhanced enterprise directory layout specified in the Enhanced Roadmap 2025.

    Options:
      --backup-only    Create backup of current data without migrating
      --dry-run        Show what would be migrated without making changes
      --force          Skip confirmation prompts
      --help           Show this help message

    Migration Process:
      1. Create backup of current data structure
      2. Initialize new enhanced directory structure
      3. Migrate users to system/users/ with enhanced fields
      4. Migrate tenants with enhanced configuration
      5. Migrate memberships to tenant-specific member records
      6. Migrate FSM data to tenant workflows structure
      7. Generate migration report

    New Directory Structure:
      ./data/
      ├── system/                    # Global platform data
      │   ├── users/user_{uuid}.json
      │   └── sessions/
      ├── tenants/                   # Tenant-isolated data
      │   ├── {tenant_uuid}/
      │   │   ├── config.json
      │   │   ├── members/member_{user_uuid}.json
      │   │   ├── workflows/{Module}/{fsm_id}.json
      │   │   └── billing/usage/
      │   └── index.json

    Safety:
      - Always creates backup before migration
      - Migration is idempotent (can be run multiple times)
      - Original data is preserved in _migration_backup/
    """
  end

  defp run_backup_only do
    IO.puts "🔄 Creating backup of current data structure..."

    case DirectoryMigrator.create_backup() do
      :ok ->
        IO.puts "✅ Backup completed successfully!"
        IO.puts "📦 Backup location: #{Path.expand("data/_migration_backup")}"

      {:error, reason} ->
        IO.puts "❌ Backup failed: #{inspect(reason)}"
        System.halt(1)
    end
  end

  defp run_dry_run do
    IO.puts "🔍 Analyzing current data structure (dry run)..."

    # Check what exists currently

    IO.puts "\n📊 Current Data Analysis:"

    # Legacy users
    users_count = count_legacy_users()
    IO.puts "   👤 Users: #{users_count}"

    # Legacy tenants
    tenants_count = count_legacy_tenants()
    IO.puts "   🏢 Tenants: #{tenants_count}"

    # Legacy memberships
    memberships_count = count_legacy_memberships()
    IO.puts "   👥 Memberships: #{memberships_count}"

    # FSM data
    fsm_data_count = count_fsm_data()
    IO.puts "   ⚙️  Workflow files: #{fsm_data_count}"

    IO.puts "\n🎯 Migration Plan:"
    IO.puts "   ✓ Create backup of current structure"
    IO.puts "   ✓ Initialize enhanced directory structure"
    IO.puts "   ✓ Migrate #{users_count} users to system/users/"
    IO.puts "   ✓ Migrate #{tenants_count} tenants with enhanced config"
    IO.puts "   ✓ Migrate #{memberships_count} memberships to tenant members/"
    IO.puts "   ✓ Migrate #{fsm_data_count} workflow files to tenant workflows/"
    IO.puts "   ✓ Generate migration report"

    IO.puts "\n📁 New Structure Preview:"
    IO.puts "   data/"
    IO.puts "   ├── system/"
    IO.puts "   │   ├── users/           (#{users_count} user files)"
    IO.puts "   │   └── sessions/"
    IO.puts "   ├── tenants/"
    IO.puts "   │   └── {tenant_id}/"
    IO.puts "   │       ├── config.json  (#{tenants_count} tenant configs)"
    IO.puts "   │       ├── members/     (#{memberships_count} member files)"
    IO.puts "   │       └── workflows/   (#{fsm_data_count} workflow files)"
    IO.puts "   └── _migration_backup/   (full backup of current data)"

    IO.puts "\n💡 To perform the actual migration, run: mix storage.migrate"
  end

  defp run_migration(opts) do
    unless opts[:force] do
      if not confirm_migration() do
        IO.puts "❌ Migration cancelled by user"
        {:ok}
      end
    end

    IO.puts "🚀 Starting TRAAVIIS storage migration to enhanced structure..."
    IO.puts "📋 Following Enhanced Roadmap 2025 Phase 1 specifications\n"

    case DirectoryMigrator.migrate_all() do
      :ok ->
        IO.puts "\n🎉 Migration completed successfully!"
        IO.puts "✅ Your TRAAVIIS data has been upgraded to the enhanced enterprise structure"
        IO.puts "\n📊 Next Steps:"
        IO.puts "   1. Verify migrated data: ls -la data/system/users/"
        IO.puts "   2. Test application functionality"
        IO.puts "   3. Review migration report: data/migration_report.json"
        IO.puts "   4. Remove backup when satisfied: rm -rf data/_migration_backup"

      {:error, reason} ->
        IO.puts "\n❌ Migration failed: #{inspect(reason)}"
        IO.puts "📦 Your original data is safely backed up in data/_migration_backup/"
        IO.puts "🔧 Please check the logs and try again, or contact support"
        System.halt(1)
    end
  end

  defp confirm_migration do
    IO.puts "⚠️  This will migrate your data to the enhanced directory structure."
    IO.puts "📦 A backup will be created automatically."
    IO.puts ""

    response = IO.gets("Continue with migration? (y/N): ")
(String.trim(response) |> String.downcase()) in ["y", "yes"]
  end

  defp count_legacy_users do
    try do
      FSMApp.Storage.FSStore.load("accounts", "users") |> length()
    rescue
      _ -> 0
    end
  end

  defp count_legacy_tenants do
    try do
      FSMApp.Storage.FSStore.load("tenancy", "tenants") |> length()
    rescue
      _ -> 0
    end
  end

  defp count_legacy_memberships do
    try do
      FSMApp.Storage.FSStore.load("tenancy", "memberships") |> length()
    rescue
      _ -> 0
    end
  end

  defp count_fsm_data do
    data_root = Path.expand("data")

    if File.exists?(data_root) do
      data_root
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(data_root, &1)))
      |> Enum.flat_map(fn dir ->
        fsm_path = Path.join([data_root, dir, "fsm"])
        if File.exists?(fsm_path) do
          count_files_recursive(fsm_path)
        else
          []
        end
      end)
      |> length()
    else
      0
    end
  end

  defp count_files_recursive(dir) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.flat_map(fn item ->
        item_path = Path.join(dir, item)
        if File.dir?(item_path) do
          count_files_recursive(item_path)
        else
          [item_path]
        end
      end)
    else
      []
    end
  end
end
