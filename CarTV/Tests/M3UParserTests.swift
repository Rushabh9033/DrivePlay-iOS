import XCTest
import CarTV

/// Covers T-001 (M3U / M3U8 playlist parser).
///
/// Verification plan for T-001: "Feed a fixture playlist with and without
/// group-title and tvg-logo tags; assert the channel count, the group
/// assignment and the artwork URL, and assert that a document not beginning
/// with #EXTM3U is rejected."
final class M3UParserTests: XCTestCase {

    private let parser = M3UParser()

    private let mixedFixture = """
    #EXTM3U
    #EXTINF:-1 tvg-id="tears.steel" tvg-logo="https://example.com/tears.jpg" group-title="Movies",Tears of Steel - 1080P
    https://example.com/tears.mp4
    #EXTINF:-1 tvg-id="agent327" tvg-logo="https://example.com/agent.jpg" group-title="Movies",Agent 327 - 4K HDR
    https://example.com/agent.mp4
    #EXTINF:-1 tvg-id="news1" group-title="Interviews",News - 1080P H.264
    https://example.com/news.mp4
    #EXTINF:-1,Sports Channel
    https://example.com/sports.mp4
    """

    // MARK: - AC: one channel per media entry, each with a name, group and optional artwork

    func test_AC1_returns_one_channel_per_media_entry() throws {
        let channels = try parser.parse(content: mixedFixture)
        XCTAssertEqual(channels.count, 4)
    }

    func test_AC1_assigns_name_and_group_from_tags() throws {
        let channels = try parser.parse(content: mixedFixture)
        XCTAssertEqual(channels[0].name, "Tears of Steel - 1080P")
        XCTAssertEqual(channels[0].groupTitle, "Movies")
        XCTAssertEqual(channels[2].groupTitle, "Interviews")
    }

    func test_AC1_assigns_artwork_only_where_tvg_logo_is_present() throws {
        let channels = try parser.parse(content: mixedFixture)
        XCTAssertEqual(channels[0].logoURL?.absoluteString, "https://example.com/tears.jpg")
        XCTAssertEqual(channels[1].logoURL?.absoluteString, "https://example.com/agent.jpg")
        XCTAssertNil(channels[2].logoURL, "entry without tvg-logo must have no artwork")
        XCTAssertNil(channels[3].logoURL, "entry without tvg-logo must have no artwork")
    }

    /// An entry with no group-title must fall back to the default group, not
    /// inherit the previous entry's group.
    func test_AC1_entry_without_group_title_does_not_inherit_previous_group() throws {
        let channels = try parser.parse(content: mixedFixture)
        XCTAssertEqual(channels[1].groupTitle, "Movies")
        XCTAssertEqual(channels[3].groupTitle, "Other", "group leaked from a previous entry")
    }

    /// Entries are grouped by group-title.
    func test_AC1_entries_are_grouped_by_group_title() throws {
        let channels = try parser.parse(content: mixedFixture)
        let grouped = Dictionary(grouping: channels, by: { $0.groupTitle })
        XCTAssertEqual(grouped["Movies"]?.count, 2)
        XCTAssertEqual(grouped["Interviews"]?.count, 1)
        XCTAssertEqual(grouped["Other"]?.count, 1)
    }

    // MARK: - AC: a document not beginning with #EXTM3U is rejected

    func test_AC1_rejects_document_not_beginning_with_extm3u() {
        XCTAssertThrowsError(try parser.parse(content: "not a playlist\nhttp://example.com/a"))
    }

    func test_AC1_rejects_empty_content() {
        XCTAssertThrowsError(try parser.parse(content: "   \n  "))
    }

    // MARK: - Title and group-tag edge cases

    /// Channel titles routinely contain commas ("Movie, The (2021)"). The comma
    /// that ends the attribute list must be found outside quoted values.
    func test_AC1_keeps_commas_inside_channel_title() throws {
        let fixture = """
        #EXTM3U
        #EXTINF:-1 tvg-id="mov1" tvg-logo="https://example.com/m.jpg" group-title="Movies",The Matrix, Reloaded (2021)
        https://example.com/1.m3u8
        """
        let channels = try parser.parse(content: fixture)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "The Matrix, Reloaded (2021)")
        XCTAssertEqual(channels[0].groupTitle, "Movies")
        XCTAssertEqual(channels[0].tvgId, "mov1")
    }

    func test_AC1_keeps_commas_inside_quoted_attribute_value() throws {
        let fixture = """
        #EXTM3U
        #EXTINF:-1 tvg-name="Movie, The",Movie, The
        https://example.com/1.m3u8
        """
        let channels = try parser.parse(content: fixture)
        XCTAssertEqual(channels[0].name, "Movie, The")
    }

    func test_AC1_keeps_title_comma_when_there_are_no_attributes() throws {
        let fixture = """
        #EXTM3U
        #EXTINF:-1,Movie, The
        https://example.com/1.m3u8
        """
        let channels = try parser.parse(content: fixture)
        XCTAssertEqual(channels[0].name, "Movie, The")
    }

    /// #EXTGRP may precede or follow the #EXTINF it belongs to, and must not
    /// leak onto the entry after it.
    func test_AC1_extgrp_applies_to_its_own_entry_only() throws {
        let fixture = """
        #EXTM3U
        #EXTGRP:Kids
        #EXTINF:-1,Kid Show
        https://example.com/kid.m3u8
        #EXTINF:-1,Adult Show
        https://example.com/adult.m3u8
        """
        let channels = try parser.parse(content: fixture)
        XCTAssertEqual(channels[0].groupTitle, "Kids")
        XCTAssertEqual(channels[1].groupTitle, "Other")
    }

    func test_AC1_extgrp_after_extinf_applies_to_that_entry() throws {
        let fixture = """
        #EXTM3U
        #EXTINF:-1,Kid Show
        #EXTGRP:Kids
        https://example.com/kid.m3u8
        """
        let channels = try parser.parse(content: fixture)
        XCTAssertEqual(channels[0].groupTitle, "Kids")
    }

    func test_AC1_explicit_group_title_wins_over_extgrp() throws {
        let fixture = """
        #EXTM3U
        #EXTINF:-1 group-title="Sports",Match
        #EXTGRP:Kids
        https://example.com/match.m3u8
        """
        let channels = try parser.parse(content: fixture)
        XCTAssertEqual(channels[0].groupTitle, "Sports")
    }

    // MARK: - Resolution label

    func test_AC1_derives_resolution_label_from_title() throws {
        let fixture = """
        #EXTM3U
        #EXTINF:-1,Feature 4K HDR
        https://example.com/1.m3u8
        #EXTINF:-1,Movie 1080P
        https://example.com/2.m3u8
        """
        let channels = try parser.parse(content: fixture)
        XCTAssertEqual(channels[0].resolutionLabel, "4K HDR")
        XCTAssertEqual(channels[1].resolutionLabel, "1080P")
    }
}
