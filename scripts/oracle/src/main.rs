use std::fs;
use serde_json::json;
fn main() {
    let dir = std::env::args().nth(1).unwrap();
    let out = std::env::args().nth(2).unwrap();
    fs::create_dir_all(&out).unwrap();
    for e in fs::read_dir(&dir).unwrap().flatten() {
        let p = e.path();
        let name = p.file_name().unwrap().to_string_lossy().to_string();
        if !name.ends_with(".logicx") { continue; }
        let pd = p.join("Alternatives/000/ProjectData");
        let Ok(raw) = fs::read(&pd) else { continue };
        let aus = lpx_parser::find_aus(&raw);
        let mut tracks = lpx_parser::find_tracks(&raw);
        lpx_parser::assign_aus(&mut tracks, &aus);
        let rr = lpx_parser::find_region_records(&raw);
        let clusters = lpx_parser::cluster_regions(&rr);
        lpx_parser::assign_user_names(&mut tracks, &clusters);
        let reg = lpx_parser::find_track_registry_records(&raw);
        lpx_parser::assign_registry_names(&mut tracks, &reg);
        lpx_parser::synthesize_folder_tracks(&mut tracks, &reg);
        let v = json!({"aus": aus, "tracks": tracks, "registry": reg, "regions": rr.len(), "clusters": clusters.len()});
        fs::write(format!("{out}/{name}.json"), serde_json::to_string_pretty(&v).unwrap()).unwrap();
    }
}
