"""Lab-only integration guards; behavioral helpers also run natively on macOS."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[4]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


class LibraryWiringTests(unittest.TestCase):
    def test_only_lab_configuration_enables_library(self):
        self.assertIn('-DHAVE_RETROARCH_LAB_LIBRARY', read('pkg/apple/ipad-lab/Lab.xcconfig'))
        self.assertNotIn('HAVE_RETROARCH_LAB_LIBRARY', read('pkg/apple/BaseConfig.xcconfig'))

    def test_objc_build_includes_screen_only_for_lab_ios(self):
        self.assertIn('#if defined(HAVE_RETROARCH_LAB_LIBRARY) && TARGET_OS_IOS\n'
                      '#ifdef HAVE_RETROARCH_LAB_STIKJIT\n'
                      '#include "../ui/drivers/cocoa/RetroArchLabJIT.m"\n'
                      '#endif\n#include "../ui/drivers/cocoa/RetroArchLabLibrary.m"',
                      read('griffin/griffin_objc.m'))

    def test_library_never_uses_filename_core_guessing(self):
        source = read('ui/drivers/cocoa/RetroArchLabLibrary.m')
        self.assertNotIn('cocoa_launch_game_by_filename', source)
        self.assertNotIn('core_info_list_get_supported_cores', source)
        self.assertIn('RALabResolveCore(assigned, installed)', source)
        self.assertIn('fill_pathname_expand_special(expanded, game.fullPath.UTF8String', source)
        self.assertIn('task_push_load_content_with_new_core_from_companion_ui', source)

    def test_emulation_is_gated_but_task_queue_remains_live(self):
        source = read('ui/drivers/cocoa/cocoa_common.m')
        self.assertIn('if (cocoa_lab_library_visible())\n   {\n'
                      '      task_queue_check();\n      return;', source)

    def test_workflow_covers_native_changes_and_checks(self):
        workflow = read('.github/workflows/ipad-lab.yml')
        for path in ('ui/drivers/cocoa/**', 'ui/drivers/ui_cocoatouch.m', 'griffin/griffin_objc.m'):
            self.assertEqual(workflow.count("- '" + path + "'"), 2)
        self.assertIn('bash pkg/apple/ipad-lab/tests/check_library.sh', workflow)

    def test_library_does_not_mutate_content_or_save_files(self):
        source = read('ui/drivers/cocoa/RetroArchLabLibrary.m')
        for operation in ('removeItemAtPath:', 'moveItemAtPath:', 'writeToFile:',
                          'CMD_EVENT_RESET', 'CMD_EVENT_LOAD_STATE'):
            self.assertNotIn(operation, source)
        self.assertIn('@"Switch games?"', source)
        self.assertIn('!jit_available()', source)

    def test_database_metadata_survives_both_playlist_loading_paths(self):
        source = read('ui/drivers/cocoa/RetroArchPlaylistManager.m')
        regular = source.split('+ (NSArray<RetroArchPlaylistGame *> * _Nonnull)getAllGames')[1]
        regular = regular.split('+ (nullable RetroArchPlaylistGame *)findGameByFilename:')[0]
        history_and_favorites = source.split('+ (NSArray<RetroArchPlaylistGame *> *)getGamesFromPlaylist:')[1]
        history_and_favorites = history_and_favorites.split('+ (NSArray<RetroArchPlaylistGame *> *)getHistoryGames')[0]
        for loader in (regular, history_and_favorites):
            self.assertIn('if (entry->db_name && *entry->db_name)', loader)
            self.assertIn('game.databaseName = [NSString stringWithUTF8String:entry->db_name];', loader)
        self.assertIn('getGamesFromPlaylist:g_defaults.content_history', source)
        self.assertIn('getGamesFromPlaylist:g_defaults.content_favorites', source)

    def test_armsx2_uses_core_arena_check_instead_of_generic_library_jit_gate(self):
        source = read('ui/drivers/cocoa/RetroArchLabLibrary.m')
        launch = source.rsplit('NSString *identifier = RALabCoreIdentifier(core);', 1)[1]
        gate = launch.split('if (!retroarch_ctl')[0]
        self.assertIn('!jit_available()', gate)
        self.assertIn('@"dolphin"', gate)
        self.assertIn('@"play"', gate)
        self.assertNotIn('@"armsx2"', gate)
        self.assertIn('CFBundleDisplayName', gate)
        self.assertIn('bundle.bundleIdentifier', gate)

    def test_artwork_uses_entry_database_even_without_regular_playlist(self):
        source = read('ui/drivers/cocoa/RetroArchLabLibrary.m')
        reload = source.split('- (void)reloadLibrary')[1].split('- (void)filterLibrary')[0]
        self.assertIn('game.system = systems[key] ?: @"Other / recent";', reload)
        self.assertNotIn('game.databaseName =', reload)
        self.assertIn('RALabArtworkPath([NSString stringWithUTF8String:directory],\n'
                      '            game.databaseName, game.system, game.title)', source)
        self.assertNotIn('stringByAppendingPathComponent:game.system', source)

    def test_all_favorites_does_not_change_shortcut_limit(self):
        source = read('ui/drivers/cocoa/RetroArchPlaylistManager.m')
        self.assertIn('maxGames:10', source)
        self.assertIn('getAllFavoriteGames', source)
        self.assertIn('maxGames:UINT32_MAX', source)


if __name__ == '__main__':
    unittest.main()
