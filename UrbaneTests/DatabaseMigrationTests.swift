import Testing
import UrbaneSchema

@Test
func m1MigrationIsRegistered() {
  #expect(UrbaneDatabaseMigrations.makeMigrator().migrations.count == 1)
}
