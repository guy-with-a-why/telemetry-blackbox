from bbcheck import banner


def test_banner_names_the_tool():
    assert banner().startswith("bbcheck")
