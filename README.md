# XIVEquip – "Equip Recommended Gear" for WoW Forever

This is a **fork** of [XIVEquip](https://www.curseforge.com/wow/addons/xivequip),
updated and adapted for **World of Warcraft: Forever** . It is no longer a straight port.

The original addon targeted modern Retail; Forever runs on a modern 12.0-era
engine but keeps the vanilla class model, so a lot had to change. Unused retail
scales have been stripped, the settings window and scales now reflect what
Forever actually offers, and the default scales for every build have been
rebuilt around Forever's stat system.

## What's new?
**Builds & talent trees**
- Replaced retail specializations with Forever's **9 classes × 3 talent trees**
  (27 trees).
- New **Builds** system: create and name builds per class, each tying together a
  **Talent Tree**, a **Scale**, and **Weapon preferences**. The active build is
  stored per character.

**Stats & default scales**
- Rebuilt default scales around Forever's stats: Strength, Agility, Intellect,
  Stamina, Spirit, Armor, Attack Power, Ranged Attack Power, Spell Power, Bonus
  Healing, **Hit** (unified), **Crit** (unified), **Expertise**, **Weapon
  Skill**, and weapon DPS.
- Removed Mastery and Versatility, which do not exist in Forever.

**Weapons**
- New **Weapon Preference / Weapon Type / Ranged** dropdowns per build:
  - Loadout style: Auto, Two-Hander, Dual Wield, One-Hander + Shield,
    One-Hander + Off-hand.
  - Weapon-type priority (Sword/Axe/Mace/Dagger/Staff/Polearm/Fist).
  - Ranged preference (Bow/Gun/Crossbow/Wand/None).
- Dual Wield requires the character actually having trained it, and all
  weapon/armor choices respect the character's trained proficiencies.

**Settings UI**
- Renamed the "Scales" tab to **"Builds"**; the specialisations selector is now
  "Talent Tree".
- Removed the unsupported Addon Integrations / provider selector (Pawn) for now.
  > I'll probably bring this back once I look into this more

**Import / export**
- Scale export/import is now a Forever-specific format (v2) carrying the build
  ID and weapon preferences.
  > These are not compatible with the original XIVEquip builds

**Persistence**
- Added a self-contained SavedVariables fallback (a CVar mirror) to work around
  the Forever beta bug where addon settings are written but not reloaded.

## License

MIT-style. See the file headers or `LICENSE` for details.

**Credits:** Inspired by the FFXIV "Equip Recommended Gear" feature and Pawn ©
their authors. Fork maintained for World of Warcraft: Forever.

## Preview

<img width="699" height="511" alt="image" src="https://github.com/user-attachments/assets/b0146b57-54f6-4ffa-8b18-f550fb5cff70" />

<img width="696" height="605" alt="image" src="https://github.com/user-attachments/assets/a2eb3638-cc8c-4f41-9e56-43e60f6e9fd3" />

<img width="774" height="957" alt="image" src="https://github.com/user-attachments/assets/3b0c2d8e-58fe-4d65-b8ae-b93a9ae18bd0" />
