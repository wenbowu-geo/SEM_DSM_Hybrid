#!/usr/bin/env python3
"""Plot Sdiff rays across a cylindrical mega-ULVZ and their geographic map.

Requires numpy, scipy, matplotlib, ObsPy, and Basemap. For example, run with
``python3 plot_sdiff_ulvz.py``. The two figures
are saved as ``sdiff_depth_section.png`` and ``sdiff_map.png`` by default.

The ULVZ is centered at 0 degrees longitude and latitude. Its 900 km
diameter is measured along the CMB; the depth section cuts through its center.
"""

import argparse
from io import BytesIO
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import FuncFormatter
from matplotlib.patches import Rectangle
from matplotlib.offsetbox import AnnotationBbox, OffsetImage
from mpl_toolkits.basemap import Basemap
from obspy.imaging.beachball import beachball
from obspy.taup import TauPyModel
from scipy.integrate import cumulative_trapezoid


EARTH_RADIUS_KM = 6371.0
CMB_DEPTH_KM = 2889.0  # iasp91 CMB depth, consistent with the ray paths
CMB_RADIUS_KM = EARTH_RADIUS_KM - CMB_DEPTH_KM
ULVZ_DIAMETER_KM = 900.0
ULVZ_HEIGHT_KM = 50.0
ULVZ_HALF_ANGLE_DEG = np.rad2deg(ULVZ_DIAMETER_KM / (2 * CMB_RADIUS_KM))
SOURCE_LON, SOURCE_LAT, SOURCE_DEPTH_KM = -52.5, 0.0, 20.0
SOURCE_MECHANISM = (30, 45, -90)  # strike, dip, rake: normal fault
RECEIVERS = [(47.5, 0.0), (52.5, 0.0), (52.5, 10.0), (52.5, -10.0)]
COLORS = ["#0072b2", "#d55e00", "#009e73", "#cc79a7"]


def great_circle(lon1, lat1, lon2, lat2, n=250):
    """Return spherical great-circle samples in geographic degrees."""
    def xyz(lon, lat):
        lon, lat = np.deg2rad([lon, lat])
        return np.array([np.cos(lat) * np.cos(lon),
                         np.cos(lat) * np.sin(lon), np.sin(lat)])

    a, b = xyz(lon1, lat1), xyz(lon2, lat2)
    omega = np.arccos(np.clip(np.dot(a, b), -1.0, 1.0))
    t = np.linspace(0, 1, n)
    if np.isclose(omega, 0):
        vec = np.repeat(a[None, :], n, axis=0)
    else:
        vec = (np.sin((1 - t) * omega)[:, None] * a
               + np.sin(t * omega)[:, None] * b) / np.sin(omega)
    lon = np.rad2deg(np.arctan2(vec[:, 1], vec[:, 0]))
    lat = np.rad2deg(np.arctan2(vec[:, 2], np.hypot(vec[:, 0], vec[:, 1])))
    return lon, lat


def ulvz_outline(n=361):
    """Small circle whose radius is 450 km along the CMB."""
    az = np.linspace(0, 2 * np.pi, n)
    radius = np.deg2rad(ULVZ_HALF_ANGLE_DEG)
    lat = np.arcsin(np.sin(radius) * np.cos(az))
    lon = np.arctan2(np.sin(radius) * np.sin(az), np.cos(radius))
    return np.rad2deg(lon), np.rad2deg(lat)


def fine_ray_path(path, ray_param, velocity_model, depth_step_km=1.0):
    """Integrate the S-ray equation at fine depth spacing with TauP's p.

    The square-root depth coordinate resolves the grazing approach to the
    CMB. Only the CMB contact points come from TauP's coarser path samples.
    """
    depth = path["depth"]
    distance = path["dist"]
    cmb_indices = np.flatnonzero(np.isclose(depth, CMB_DEPTH_KM))
    if len(cmb_indices) < 2:
        raise ValueError("Expected an Sdiff ray with a CMB segment")
    first, last = cmb_indices[0], cmb_indices[-1]

    # For a spherical ray, sin(i) = p*v/r and
    # |d(theta)/dz| = p*v / (r*sqrt(r**2 - (p*v)**2)).
    # With u=sqrt(CMB_depth-z), the CMB singularity becomes integrable.
    u = np.linspace(0, np.sqrt(CMB_DEPTH_KM), 20000)
    z = CMB_DEPTH_KM - u * u
    layers = velocity_model.layers
    layer_index = np.clip(np.searchsorted(layers["bot_depth"], z, side="left"),
                          0, len(layers) - 1)
    selected = layers[layer_index]
    velocity = (selected["top_s_velocity"]
                + (selected["bot_s_velocity"] - selected["top_s_velocity"])
                * (z - selected["top_depth"])
                / (selected["bot_depth"] - selected["top_depth"]))
    radius = EARTH_RADIUS_KM - z
    sine_i = ray_param * velocity / radius
    integrand = np.empty_like(u)
    integrand[1:] = (2 * u[1:] * sine_i[1:]
                     / (radius[1:] * np.sqrt(1 - sine_i[1:] ** 2)))
    integrand[0] = integrand[1]
    angle_from_cmb = cumulative_trapezoid(integrand, u, initial=0)

    def angular_offset(depth_samples):
        return np.interp(np.sqrt(CMB_DEPTH_KM - depth_samples),
                         u, angle_from_cmb)

    inward_z = np.r_[np.arange(depth[0], CMB_DEPTH_KM, depth_step_km),
                     CMB_DEPTH_KM]
    inward_phi = distance[first] - angular_offset(inward_z)
    outward_z = np.r_[np.arange(depth[-1], CMB_DEPTH_KM, depth_step_km),
                      CMB_DEPTH_KM][::-1]
    outward_phi = distance[last] + angular_offset(outward_z)
    inward_phi[0], outward_phi[-1] = distance[0], distance[-1]
    arc_length_km = (distance[last] - distance[first]) * CMB_RADIUS_KM
    n_cmb = max(2, int(np.ceil(arc_length_km / depth_step_km)) + 1)
    cmb_phi = np.linspace(distance[first], distance[last], n_cmb)
    cmb_z = np.full(n_cmb, CMB_DEPTH_KM)

    return (np.r_[inward_phi[:-1], cmb_phi, outward_phi[1:]],
            np.r_[inward_z[:-1], cmb_z, outward_z[1:]])


def add_source_beachball(ax, xy):
    """Place an undistorted double-couple beachball at an axes data point."""
    png = beachball(SOURCE_MECHANISM, width=100, linewidth=1.5,
                    facecolor="#202020", bgcolor="white", edgecolor="black",
                    format="png")
    symbol = AnnotationBbox(OffsetImage(plt.imread(BytesIO(png), format="png"),
                                         zoom=0.22),
                            xy, frameon=False, annotation_clip=False,
                            zorder=8)
    ax.add_artist(symbol)


def plot_depth_section(model, output, dpi):
    fig, ax = plt.subplots(figsize=(11, 7), subplot_kw={"projection": "polar"})
    ax.set_theta_zero_location("N")
    ax.set_theta_direction(-1)
    ax.set_thetamin(-75)
    ax.set_thetamax(75)
    ax.set_rlim(CMB_RADIUS_KM, EARTH_RADIUS_KM)
    ax.set_rorigin(0)
    ax.set_facecolor("#f8f5ed")
    ax.grid(color="#c8c8c8", alpha=0.75, linewidth=0.7)

    theta = np.deg2rad(np.linspace(-75, 75, 600))
    ax.plot(theta, np.full_like(theta, CMB_RADIUS_KM), color="#555555",
            linewidth=2, label="CMB", zorder=3)
    ax.bar(0, ULVZ_HEIGHT_KM, width=np.deg2rad(2 * ULVZ_HALF_ANGLE_DEG),
           bottom=CMB_RADIUS_KM, align="center", color="#4c4c4c",
           edgecolor="#303030", linewidth=0.8, label="Mega-ULVZ", zorder=4)

    # At full mantle scale the 20 km height is only a few pixels. Show it
    # separately at true dimensions in a local, flat CMB close-up.
    zoom = fig.add_axes([0.68, 0.73, 0.25, 0.15])
    zoom.add_patch(Rectangle((-ULVZ_DIAMETER_KM / 2,
                              CMB_DEPTH_KM - ULVZ_HEIGHT_KM),
                             ULVZ_DIAMETER_KM, ULVZ_HEIGHT_KM,
                             facecolor="#4c4c4c", edgecolor="#303030"))
    zoom.axhline(CMB_DEPTH_KM, color="#555555", linewidth=1)

    for lon, color in zip((47.5, 52.5), COLORS):
        distance = lon - SOURCE_LON
        arrivals = model.get_ray_paths(source_depth_in_km=SOURCE_DEPTH_KM,
                                       distance_in_degree=distance,
                                       phase_list=["Sdiff"])
        if not arrivals:
            raise RuntimeError(f"No Sdiff path for {distance:.1f}° in iasp91")
        path = arrivals[0].path
        ray_distance, ray_depth = fine_ray_path(
            path, arrivals[0].ray_param, model.model.s_mod.v_mod,
            depth_step_km=1.0)
        theta_ray = np.deg2rad(SOURCE_LON) + ray_distance
        radius_ray = EARTH_RADIUS_KM - ray_depth
        ax.plot(theta_ray, radius_ray, color=color, linewidth=2.1,
                label=f"Sdiff to {lon:g}° ({distance:g}°)", zorder=5)
        x_km = theta_ray * CMB_RADIUS_KM
        zoom.plot(x_km, ray_depth, color=color, linewidth=1.5)
        ax.scatter(np.deg2rad(lon), EARTH_RADIUS_KM, marker="^", s=95,
                   facecolor=color, edgecolor="black", linewidth=0.6,
                   zorder=7, clip_on=False)

    add_source_beachball(ax, (np.deg2rad(SOURCE_LON),
                              EARTH_RADIUS_KM - SOURCE_DEPTH_KM))
    fig.text(0.07, 0.85, "Source: normal fault, 30° strike, 45° dip, -90° rake",
             fontsize=9)
    ax.set_thetagrids(np.arange(-75, 76, 15),
                      labels=[f"{v}°" for v in range(-75, 76, 15)])
    ax.set_rticks(EARTH_RADIUS_KM - np.array([0, 1000, 2000, CMB_DEPTH_KM]))
    ax.yaxis.set_major_formatter(
        FuncFormatter(lambda radius, _pos: f"{EARTH_RADIUS_KM - radius:.0f} km"))
    ax.set_rlabel_position(69)
    ax.set_title("Sdiff ray paths and mega-ULVZ at the CMB", pad=20, fontsize=14)
    zoom.set_xlim(-1000, 1000)
    zoom.set_ylim(CMB_DEPTH_KM + 5, CMB_DEPTH_KM - 65)
    zoom.set_xticks([-900, 0, 900])
    zoom.set_yticks([CMB_DEPTH_KM - 40,
                     CMB_DEPTH_KM - ULVZ_HEIGHT_KM, CMB_DEPTH_KM])
    zoom.tick_params(labelsize=7)
    zoom.set_xlabel("Distance from 0° (km)", fontsize=7)
    zoom.set_ylabel("Depth (km)", fontsize=7)
    zoom.set_title("CMB close-up", fontsize=9)
    ax.legend(loc="lower center", bbox_to_anchor=(0.5, -0.08), ncol=3,
              frameon=False, fontsize=9)
    fig.savefig(output, dpi=dpi, bbox_inches="tight")
    plt.close(fig)


def plot_map(output, dpi):
    fig, ax = plt.subplots(figsize=(11, 6.5))
    m = Basemap(projection="cyl", llcrnrlon=-75, urcrnrlon=75,
                llcrnrlat=-30, urcrnrlat=30, resolution="l", ax=ax)
    m.drawmapboundary(fill_color="#e7f0f4", linewidth=0.8)
    m.fillcontinents(color="#eeece6", lake_color="#e7f0f4", zorder=1)
    m.drawcoastlines(color="#999999", linewidth=0.5, zorder=2)
    m.drawparallels(np.arange(-30, 31, 15), color="#b5c1c6",
                    linewidth=0.5, dashes=[2, 3], labels=[1, 0, 0, 0],
                    fontsize=9)
    m.drawmeridians(np.arange(-60, 61, 20), color="#b5c1c6",
                    linewidth=0.5, dashes=[2, 3], labels=[0, 0, 0, 1],
                    fontsize=9)

    ulon, ulat = ulvz_outline()
    ax.fill(ulon, ulat, color="#4c4c4c", alpha=0.93,
            label="Mega-ULVZ (900 km diameter)", zorder=3)
    ax.plot(ulon, ulat, color="#303030", linewidth=1, zorder=4)

    for i, ((lon, lat), color) in enumerate(zip(RECEIVERS, COLORS), 1):
        glon, glat = great_circle(SOURCE_LON, SOURCE_LAT, lon, lat)
        ax.plot(glon, glat, color=color, linewidth=1.5, alpha=0.9, zorder=5)
        ax.scatter(lon, lat, marker="^", s=105, facecolor=color,
                   edgecolor="black", linewidth=0.6, zorder=7)
        offset = (-8, 9) if i == 1 else ((8, 9) if lat >= 0 else (8, -9))
        ax.annotate(f"R{i}", (lon, lat), xytext=offset,
                    textcoords="offset points", fontsize=9,
                    ha="right" if i == 1 else "left",
                    va="bottom" if lat >= 0 else "top")

    add_source_beachball(ax, (SOURCE_LON, SOURCE_LAT))
    ax.annotate("Source (-52.5°, 0°)", (SOURCE_LON, SOURCE_LAT),
                xytext=(20, 18), textcoords="offset points", fontsize=9)
    ax.set_title("Source, receivers, and mega-ULVZ footprint", pad=14, fontsize=14)
    ax.legend(loc="lower left", framealpha=0.95, fontsize=9)
    fig.tight_layout()
    fig.savefig(output, dpi=dpi, bbox_inches="tight")
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outdir", type=Path, default=Path("."),
                        help="Directory for the two PNG figures")
    parser.add_argument("--dpi", type=int, default=200)
    args = parser.parse_args()
    args.outdir.mkdir(parents=True, exist_ok=True)
    model = TauPyModel(model="iasp91")
    section = args.outdir / "sdiff_depth_section.png"
    map_file = args.outdir / "sdiff_map.png"
    plot_depth_section(model, section, args.dpi)
    plot_map(map_file, args.dpi)
    print(f"Saved {section} and {map_file}")


if __name__ == "__main__":
    main()

